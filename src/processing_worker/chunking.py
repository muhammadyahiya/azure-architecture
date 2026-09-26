"""
Token-aware sliding-window chunking. Deliberately simple and dependency-light
(word-count based) so it's easy to read and replace — swap in a
structure-aware chunker (heading-aware for markdown, page-aware for PDF via
Azure AI Document Intelligence layout output) per project without touching
anything else in the pipeline.
"""
from dataclasses import dataclass


@dataclass
class Chunk:
    chunk_id: str
    text: str
    position: int


def chunk_text(document_id: str, text: str, target_words: int = 350, overlap_words: int = 50) -> list[Chunk]:
    words = text.split()
    if not words:
        return []

    chunks: list[Chunk] = []
    start = 0
    position = 0
    step = max(target_words - overlap_words, 1)

    while start < len(words):
        end = min(start + target_words, len(words))
        chunk_words = words[start:end]
        chunks.append(
            Chunk(
                chunk_id=f"{document_id}-{position}",
                text=" ".join(chunk_words),
                position=position,
            )
        )
        position += 1
        if end == len(words):
            break
        start += step

    return chunks
