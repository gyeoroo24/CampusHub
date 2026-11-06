"""Run the matcher locally.

    python -m app.matching --backfill          match every pending open report
    python -m app.matching lost <report id>    match one report
"""
import asyncio
import logging
import sys

from .handler import _handle

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    args = sys.argv[1:]
    if args == ["--backfill"]:
        event = {"backfill": True}
    elif len(args) == 2:
        event = {"kind": args[0], "report_id": args[1]}
    else:
        sys.exit(__doc__)
    print(asyncio.run(_handle(event)))
