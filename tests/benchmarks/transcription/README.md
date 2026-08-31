# Benchmark privado de transcripción F3

Este directorio contiene SOLO harness, manifest de ejemplo y scoring. No contiene audio real ni transcripciones privadas.

## Gate documental
No se congela `transcription_primary` sin:
- ground truth humano;
- dataset privado de 25–40 clips, recomendado 45–90 minutos totales;
- OpenAI `gpt-transcribe`;
- Gemini `gemini-3.5-transcribe`;
- métricas comparables;
- errores críticos de nombres, fechas, horas y números;
- costo y latencia;
- evidencia sanitizada.

## Cobertura mínima recomendada
Audio limpio, calle, auto, reverberación, celular, nombres propios, proyectos, números, fechas/horas, acento argentino, habla rápida, disfluencias y al menos algunos clips multi-speaker.

## Privacidad
No versionar:
- audio privado;
- transcript literal privado;
- API keys;
- headers;
- IDs personales.

Git puede conservar manifest sanitizado, hashes, métricas agregadas y decisión final.

## Resultado
Si no existe dataset/ground truth/credenciales DEV, reportar:
`F3 IMPLEMENTED_PENDING_EXTERNAL_BENCHMARK`
y mantener `transcription_primary = null`.
