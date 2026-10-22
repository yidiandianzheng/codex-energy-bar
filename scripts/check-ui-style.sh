#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1]) / 'Sources/CodexPetEnergy'
issues = []
for path in sorted(root.glob('*.swift')):
    if path.name in {'EnergyTypography.swift', 'EnergyVisualStyle.swift'}:
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if '.font(' in line and 'EnergyTypography.' not in line:
            issues.append(f'{path.name}:{number}: font must reference EnergyTypography')
        if re.search(r'Color\(red:|Color\(nsColor: \.system|\.(?:blue|cyan|teal|orange|purple|pink)\b', line):
            issues.append(f'{path.name}:{number}: color must reference EnergyVisualStyle')
if issues:
    print('\n'.join(issues))
    sys.exit(1)
print('UI style check passed: typography roles and monochrome palette')
PY
