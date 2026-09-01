import io
import os
import zipfile
from typing import Tuple, List, Optional


class DocxValidationError(Exception):
    def __init__(self, error_code: str, message: str, http_status: int = 400):
        super().__init__(message)
        self.error_code = error_code
        self.message = message
        self.http_status = http_status


# Defensive guardrails (configurable via env if needed, with secure defaults)
MAX_ZIP_ENTRIES = int(os.getenv("DOCX_MAX_ZIP_ENTRIES", "1000"))
MAX_UNCOMPRESSED_BYTES = int(os.getenv("DOCX_MAX_UNCOMPRESSED_BYTES", "104857600"))  # 100 MB
MAX_COMPRESSION_RATIO = float(os.getenv("DOCX_MAX_COMPRESSION_RATIO", "100.0"))     # 100x


def validate_docx_preflight(
    data: bytes,
    max_entries: int = MAX_ZIP_ENTRIES,
    max_uncompressed_bytes: int = MAX_UNCOMPRESSED_BYTES,
    max_compression_ratio: float = MAX_COMPRESSION_RATIO
) -> Tuple[zipfile.ZipFile, List[str]]:
    """
    Validates DOCX binary container defensivel prior to parsing.
    Returns the open ZipFile and a list of warnings.
    """
    if not data or len(data) == 0:
        raise DocxValidationError("DOCX_EMPTY", "Provided DOCX file is empty", 400)

    # Magic number check for PKZip
    if not data.startswith(b"PK\x03\x04") and not data.startswith(b"PK\x05\x06") and not data.startswith(b"PK\x07\x08"):
        raise DocxValidationError("DOCX_INVALID", "File does not have a valid ZIP/DOCX header", 400)

    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except Exception as e:
        raise DocxValidationError("DOCX_INVALID", f"Corrupt or malformed ZIP archive: {str(e)}", 400)

    infolist = zf.infolist()
    if len(infolist) == 0:
        raise DocxValidationError("DOCX_EMPTY", "DOCX archive contains no files", 400)

    if len(infolist) > max_entries:
        raise DocxValidationError("ZIP_GUARDRAIL_EXCEEDED", f"ZIP entry count ({len(infolist)}) exceeds limit ({max_entries})", 400)

    total_uncompressed = 0
    total_compressed = 0
    has_content_types = False
    has_word_doc = False
    warnings = []

    for info in infolist:
        fname = info.filename
        
        # 1. Path Traversal & Absolute Path checks
        if ".." in fname or fname.startswith("/") or fname.startswith("\\") or (len(fname) > 1 and fname[1] == ":"):
            raise DocxValidationError("PATH_TRAVERSAL_DETECTED", f"Dangerous path traversal in archive: {fname}", 400)

        # 2. Encrypted entry check
        if info.flag_bits & 0x1:
            raise DocxValidationError("DOCX_ENCRYPTED", "Encrypted DOCX entries are not supported", 400)

        # 3. Macro checks (.docm / vbaProject.bin)
        if "vbaProject.bin" in fname or fname.lower().endswith(".vba"):
            raise DocxValidationError("UNSUPPORTED_MACRO_ENABLED_OFFICE", "Macro-enabled Word documents (.docm / VBA) are strictly rejected", 400)

        # 4. Track OpenXML structural requirements
        if fname == "[Content_Types].xml":
            has_content_types = True
        if fname == "word/document.xml":
            has_word_doc = True

        total_uncompressed += info.file_size
        total_compressed += info.compress_size

        if total_uncompressed > max_uncompressed_bytes:
            raise DocxValidationError("ZIP_GUARDRAIL_EXCEEDED", f"Total uncompressed size exceeds limit ({max_uncompressed_bytes} bytes)", 400)

    # 5. Compression ratio check (ZIP bomb protection)
    effective_compressed = max(total_compressed, 1)
    ratio = total_uncompressed / effective_compressed
    if ratio > max_compression_ratio and total_uncompressed > 1024 * 1024:
        raise DocxValidationError("ZIP_GUARDRAIL_EXCEEDED", f"ZIP compression ratio ({ratio:.1f}x) exceeds limit ({max_compression_ratio}x)", 400)

    # 6. Structure validation
    if not has_content_types or not has_word_doc:
        raise DocxValidationError("DOCX_INVALID", "Archive missing required OpenXML components ([Content_Types].xml or word/document.xml)", 400)

    return zf, warnings
