-- Migration: 20260831000013_f3_media_drive_runtime.sql
-- Baseline: SVIA-DOCSET-V1-RC1
-- Phase: F3 Audio + Drive
-- IMPORTANT: creates NO product tables; 25-table V1 model is preserved.

BEGIN;

CREATE OR REPLACE FUNCTION public.set_ingestion_media_status(
  p_user_id uuid,
  p_ingestion_id uuid,
  p_status text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.ingestions%ROWTYPE;
BEGIN
  IF p_status NOT IN ('received','processing','waiting_clarification','awaiting_external_file','completed','error','duplicate') THEN
    RAISE EXCEPTION 'Invalid ingestion status';
  END IF;

  SELECT * INTO v_row
  FROM public.ingestions
  WHERE id = p_ingestion_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Ingestion not found for user'; END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'Unauthorized ingestion mutation';
  END IF;

  UPDATE public.ingestions
  SET status = p_status,
      processing_started_at = CASE WHEN p_status = 'processing' AND processing_started_at IS NULL THEN pg_catalog.now() ELSE processing_started_at END,
      completed_at = CASE WHEN p_status = 'completed' THEN pg_catalog.now() ELSE completed_at END,
      last_error_code = CASE WHEN p_status = 'error' THEN p_error_code ELSE last_error_code END,
      last_error_message = CASE WHEN p_status = 'error' THEN left(p_error_message, 500) ELSE last_error_message END,
      updated_at = pg_catalog.now()
  WHERE id = p_ingestion_id AND user_id = p_user_id;

  RETURN pg_catalog.jsonb_build_object('ok',true,'ingestion_id',p_ingestion_id,'status',p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_asset_with_location(
  p_user_id uuid,
  p_ingestion_id uuid,
  p_sha256 text,
  p_media_kind text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_duration_ms bigint,
  p_location_type text,
  p_external_id text,
  p_drive_file_id text DEFAULT NULL,
  p_telegram_file_id text DEFAULT NULL,
  p_telegram_chat_id bigint DEFAULT NULL,
  p_telegram_message_id bigint DEFAULT NULL,
  p_path_hint text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_asset_id uuid;
  v_location_id uuid;
  v_existing_location_asset uuid;
  v_created boolean := false;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'Unauthorized asset mutation';
  END IF;
  IF p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid SHA-256'; END IF;
  IF p_location_type NOT IN ('drive','telegram','nas_backup','generated','external') THEN RAISE EXCEPTION 'Invalid location type'; END IF;
  IF p_external_id IS NULL OR length(trim(p_external_id)) = 0 THEN RAISE EXCEPTION 'Versioned external_id is required'; END IF;
  IF p_size_bytes IS NOT NULL AND p_size_bytes < 0 THEN RAISE EXCEPTION 'Invalid size'; END IF;
  IF p_duration_ms IS NOT NULL AND p_duration_ms < 0 THEN RAISE EXCEPTION 'Invalid duration'; END IF;

  PERFORM 1 FROM public.ingestions WHERE id = p_ingestion_id AND user_id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ingestion not found for user'; END IF;

  SELECT id INTO v_asset_id
  FROM public.assets WHERE user_id = p_user_id AND sha256 = p_sha256;

  IF v_asset_id IS NULL THEN
    INSERT INTO public.assets(
      user_id,first_ingestion_id,sha256,original_filename,mime_type,media_kind,
      size_bytes,duration_ms,integrity_status,storage_status
    ) VALUES (
      p_user_id,p_ingestion_id,p_sha256,p_original_filename,p_mime_type,p_media_kind,
      p_size_bytes,p_duration_ms,'verified','available'
    )
    RETURNING id INTO v_asset_id;
    v_created := true;
  ELSE
    UPDATE public.assets
    SET original_filename = COALESCE(original_filename,p_original_filename),
        mime_type = COALESCE(mime_type,p_mime_type),
        size_bytes = COALESCE(size_bytes,p_size_bytes),
        duration_ms = COALESCE(duration_ms,p_duration_ms)
    WHERE id = v_asset_id AND user_id = p_user_id;
  END IF;

  SELECT asset_id INTO v_existing_location_asset
  FROM public.asset_locations
  WHERE user_id = p_user_id AND location_type = p_location_type AND external_id = p_external_id;

  IF v_existing_location_asset IS NOT NULL AND v_existing_location_asset <> v_asset_id THEN
    RAISE EXCEPTION 'External location already points to a different historical asset; use a versioned external_id';
  END IF;

  INSERT INTO public.asset_locations(
    user_id,asset_id,location_type,external_id,drive_file_id,telegram_file_id,
    telegram_chat_id,telegram_message_id,path_hint,is_primary,is_available,metadata,last_verified_at
  ) VALUES (
    p_user_id,v_asset_id,p_location_type,p_external_id,p_drive_file_id,p_telegram_file_id,
    p_telegram_chat_id,p_telegram_message_id,p_path_hint,(p_location_type='drive'),true,
    COALESCE(p_metadata,'{}'::jsonb),pg_catalog.now()
  )
  ON CONFLICT (user_id,location_type,external_id) WHERE external_id IS NOT NULL
  DO UPDATE SET
    is_available = true,
    last_verified_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  RETURNING id INTO v_location_id;

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,'asset_id',v_asset_id,'location_id',v_location_id,'asset_created',v_created
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_source_text_variant(
  p_user_id uuid,
  p_ingestion_id uuid,
  p_asset_id uuid,
  p_source_type text,
  p_text_content text,
  p_language text,
  p_provider text,
  p_model text,
  p_prompt_version text DEFAULT NULL,
  p_make_preferred boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source_key text;
  v_existing uuid;
  v_existing_version integer;
  v_version integer;
  v_new uuid;
  v_prev uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN RAISE EXCEPTION 'Unauthorized source_text mutation'; END IF;
  IF p_text_content IS NULL OR length(p_text_content) = 0 THEN RAISE EXCEPTION 'Empty source text'; END IF;
  PERFORM 1 FROM public.ingestions WHERE id=p_ingestion_id AND user_id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ingestion not found for user'; END IF;
  PERFORM 1 FROM public.assets WHERE id=p_asset_id AND user_id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found for user'; END IF;

  v_source_key := 'asset:' || p_asset_id::text || ':' || p_source_type;

  SELECT id,version_no INTO v_existing,v_existing_version
  FROM public.source_texts
  WHERE user_id=p_user_id AND source_key=v_source_key
    AND provider IS NOT DISTINCT FROM p_provider
    AND model IS NOT DISTINCT FROM p_model
    AND text_content=p_text_content
  ORDER BY version_no DESC LIMIT 1;

  IF v_existing IS NOT NULL THEN
    IF p_make_preferred THEN
      UPDATE public.source_texts SET is_preferred=false,updated_at=pg_catalog.now()
      WHERE user_id=p_user_id AND source_key=v_source_key AND id<>v_existing AND is_preferred=true;
      UPDATE public.source_texts SET is_preferred=true,updated_at=pg_catalog.now() WHERE id=v_existing;
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok',true,'source_text_id',v_existing,'version_no',v_existing_version,'is_replay',true);
  END IF;

  SELECT id INTO v_prev
  FROM public.source_texts
  WHERE user_id=p_user_id AND source_key=v_source_key
  ORDER BY version_no DESC LIMIT 1;

  SELECT COALESCE(max(version_no),0)+1 INTO v_version
  FROM public.source_texts WHERE user_id=p_user_id AND source_key=v_source_key;

  IF p_make_preferred THEN
    UPDATE public.source_texts SET is_preferred=false,updated_at=pg_catalog.now()
    WHERE user_id=p_user_id AND source_key=v_source_key AND is_preferred=true;
  END IF;

  INSERT INTO public.source_texts(
    user_id,ingestion_id,asset_id,source_type,source_key,version_no,text_content,
    language,provider,model,prompt_version,is_preferred,supersedes_source_text_id
  ) VALUES (
    p_user_id,p_ingestion_id,p_asset_id,p_source_type,v_source_key,v_version,p_text_content,
    p_language,p_provider,p_model,p_prompt_version,p_make_preferred,v_prev
  )
  RETURNING id INTO v_new;

  RETURN pg_catalog.jsonb_build_object('ok',true,'source_text_id',v_new,'version_no',v_version,'is_replay',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_media_ai_usage(
  p_user_id uuid,
  p_ingestion_id uuid,
  p_asset_id uuid,
  p_operation_type text,
  p_provider text,
  p_model text,
  p_model_version text DEFAULT NULL,
  p_provider_request_id text DEFAULT NULL,
  p_input_tokens bigint DEFAULT NULL,
  p_output_tokens bigint DEFAULT NULL,
  p_audio_seconds numeric DEFAULT NULL,
  p_image_count integer DEFAULT NULL,
  p_estimated_cost_usd numeric DEFAULT NULL,
  p_pricing_version text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN RAISE EXCEPTION 'Unauthorized AI usage mutation'; END IF;
  PERFORM 1 FROM public.ingestions WHERE id=p_ingestion_id AND user_id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ingestion not found for user'; END IF;
  PERFORM 1 FROM public.assets WHERE id=p_asset_id AND user_id=p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found for user'; END IF;

  INSERT INTO public.ai_usage_events(
    user_id,operation_type,provider,model,model_version,provider_request_id,
    input_tokens,output_tokens,audio_seconds,image_count,estimated_cost_usd,pricing_version,
    ingestion_id,asset_id,metadata
  ) VALUES (
    p_user_id,p_operation_type,p_provider,p_model,p_model_version,p_provider_request_id,
    p_input_tokens,p_output_tokens,p_audio_seconds,p_image_count,p_estimated_cost_usd,p_pricing_version,
    p_ingestion_id,p_asset_id,COALESCE(p_metadata,'{}'::jsonb)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_ingestion_media_status(uuid,uuid,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.upsert_asset_with_location(uuid,uuid,text,text,text,text,bigint,bigint,text,text,text,text,bigint,bigint,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_source_text_variant(uuid,uuid,uuid,text,text,text,text,text,text,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_media_ai_usage(uuid,uuid,uuid,text,text,text,text,text,bigint,bigint,numeric,integer,numeric,text,jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.set_ingestion_media_status(uuid,uuid,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_asset_with_location(uuid,uuid,text,text,text,text,bigint,bigint,text,text,text,text,bigint,bigint,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_source_text_variant(uuid,uuid,uuid,text,text,text,text,text,text,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_media_ai_usage(uuid,uuid,uuid,text,text,text,text,text,bigint,bigint,numeric,integer,numeric,text,jsonb) TO service_role;

COMMIT;
