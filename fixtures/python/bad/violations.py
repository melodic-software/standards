"""Bad fixture: intentional ruff + pyright violations. Excluded from self-lint."""

import os.path
import sys
from datetime import datetime


def build(name):
    created = datetime.now()
    location = os.path.join("/var/tmp", name)
    count: int = "not an integer"
    return location
