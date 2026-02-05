"""Shared logging helpers using structlog + Logfire."""

from __future__ import annotations

import logging

import logfire
import structlog
import structlog.contextvars

_logfire_ready = False


def _ensure_logfire() -> None:
    global _logfire_ready
    if _logfire_ready:
        return
    logfire.configure(send_to_logfire="if-token-present")
    logfire.instrument_pydantic()
    _logfire_ready = True


def configure_logging(verbose: bool = False) -> None:
    """Configure structlog + Logfire + stdlib logging for CLI tools."""

    _ensure_logfire()

    level = logging.DEBUG if verbose else logging.INFO
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(logging.Formatter("%(message)s"))
    logging.basicConfig(level=level, handlers=[stream_handler], force=True)

    timestamper = structlog.processors.TimeStamper(fmt="%Y-%m-%d %H:%M:%S", utc=True)
    renderer: structlog.types.Processor
    if verbose:
        renderer = structlog.dev.ConsoleRenderer()
    else:
        renderer = structlog.processors.KeyValueRenderer(
            key_order=["timestamp", "level", "logger", "event"],
            drop_missing=True,
        )

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            timestamper,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            logfire.StructlogProcessor(),
            renderer,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
