"""AP-only twelve-slot TAP1 profile; stock seven + display/navigation/music/reader/focus."""
import struct
import menu9_profile as old
WRAPPERS=old.WRAPPERS
REPLACEMENTS=old.REPLACEMENTS
ALIASES=old.ALIASES
# Twelve items (didi ride and app-runtime shelf removed 2026-10-14): the
# launcher carousel spring upper bounds follow the author's count-1 formula
# (menu8: 7.0/7.4667, menu9: 8.0/8.4667, fourteen: 13.0/13.4667 -> twelve: 11.0/11.4667).
PATCHES=[
 (0x1079a2b8,'f1ee087a','f2ee067a','wheel target maximum 6.0 -> 11.0 (twelve items)'),
 (0x107992f0,'efeece40',struct.pack('<f',11.4666667).hex(),'follow upper 11.4667 (twelve items)'),
 (0x10799328,'efeece40',struct.pack('<f',11.4666667).hex(),'spring upper 11.4667 (twelve items)'),
]
