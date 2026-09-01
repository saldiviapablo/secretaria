import io
from typing import Dict, Any, List
import docx
from docx.text.paragraph import Paragraph
from docx.table import Table

from app.validation import validate_docx_preflight, DocxValidationError


def extract_text_from_docx(data: bytes) -> Dict[str, Any]:
    """
    Extracts text and metadata from DOCX bytes deterministically.
    Preserves relative order between paragraphs and tables.
    """
    zf, warnings = validate_docx_preflight(data)
    zf.close()

    try:
        doc = docx.Document(io.BytesIO(data))
    except Exception as e:
        raise DocxValidationError("DOCX_PARSE_FAILED", f"Failed to parse document: {str(e)}", 400)

    extracted_blocks: List[str] = []
    paragraph_count = 0
    table_count = 0

    # python-docx 1.1+ supports iter_inner_content() to traverse elements in document order
    if hasattr(doc, "iter_inner_content"):
        elements = doc.iter_inner_content()
    else:
        # Fallback element traversal for older python-docx
        elements = []
        for child in doc.element.body:
            if child.tag.endswith("p"):
                elements.append(Paragraph(child, doc))
            elif child.tag.endswith("tbl"):
                elements.append(Table(child, doc))

    for item in elements:
        if isinstance(item, Paragraph):
            p_text = item.text.strip()
            if p_text:
                extracted_blocks.append(p_text)
                paragraph_count += 1
        elif isinstance(item, Table):
            table_count += 1
            table_lines: List[str] = []
            for row in item.rows:
                cell_texts = [cell.text.replace("\n", " ").strip() for cell in row.cells]
                # Avoid duplicate identical cell texts across merged columns
                # by basic deduplication or tab joining
                table_lines.append("\t".join(cell_texts))
            if table_lines:
                extracted_blocks.append("\n".join(table_lines))

    # Check for embedded objects or images to add warnings
    try:
        inline_shapes = doc.inline_shapes
        if len(inline_shapes) > 0:
            warnings.append(f"Document contains {len(inline_shapes)} embedded shapes/images; visual content is preserved in original but not OCR-extracted.")
    except Exception:
        pass

    final_text = "\n\n".join(extracted_blocks).strip()
    char_count = len(final_text)

    if char_count == 0 and not warnings:
        warnings.append("Document extracted with zero textual content.")

    return {
        "status": "ok",
        "extractor": "python-docx",
        "extractor_version": getattr(docx, "__version__", "1.2.0"),
        "text": final_text,
        "metadata": {
            "paragraph_count": paragraph_count,
            "table_count": table_count,
            "character_count": char_count
        },
        "warnings": warnings
    }
