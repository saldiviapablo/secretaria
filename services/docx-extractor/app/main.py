from fastapi import FastAPI, Request, Response, HTTPException, status
from fastapi.responses import JSONResponse
from app.validation import DocxValidationError
from app.extractor import extract_text_from_docx

app = FastAPI(
    title="SVIA DOCX Extractor",
    description="Deterministic, secure DOCX text extractor sidecar service",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None
)


@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    return {"status": "ok"}


@app.post("/v1/extract/docx")
async def extract_docx_endpoint(request: Request):
    content_type = request.headers.get("content-type", "").lower()
    
    # Read raw binary payload
    try:
        body = await request.body()
    except Exception as e:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={
                "status": "error",
                "error_code": "REQUEST_BODY_READ_FAILED",
                "message": "Failed to read request body"
            }
        )

    if not body:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={
                "status": "error",
                "error_code": "DOCX_EMPTY",
                "message": "Empty DOCX payload provided"
            }
        )

    # Basic MIME validation if supplied
    if "application/vnd.ms-word.document.macroenabled" in content_type:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={
                "status": "error",
                "error_code": "UNSUPPORTED_MACRO_ENABLED_OFFICE",
                "message": "Macro-enabled documents are quarantined and not extracted"
            }
        )

    try:
        result = extract_text_from_docx(body)
        return JSONResponse(status_code=status.HTTP_200_OK, content=result)
    except DocxValidationError as e:
        return JSONResponse(
            status_code=e.http_status,
            content={
                "status": "error",
                "error_code": e.error_code,
                "message": e.message
            }
        )
    except Exception as e:
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={
                "status": "error",
                "error_code": "EXTRACTION_FAILED",
                "message": "Internal error during DOCX extraction"
            }
        )
