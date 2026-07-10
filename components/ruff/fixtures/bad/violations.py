"""Bad fixture: intentional Ruff violations. Excluded from self-lint."""

import os.path
import sys
from datetime import datetime


def build(name):
    created = datetime.now()
    location = os.path.join("/var/tmp", name)
    count: int = "not an integer"
    handle = open("x")
    banner = "implicit" "concat"
    return location
