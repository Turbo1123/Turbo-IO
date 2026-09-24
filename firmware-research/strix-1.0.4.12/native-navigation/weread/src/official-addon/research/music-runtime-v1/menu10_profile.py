"""AP-only ten-slot profile; stock seven, display, navigation, music."""
import struct
import menu9_profile as old
WRAPPERS=old.WRAPPERS
REPLACEMENTS=old.REPLACEMENTS
ALIASES=old.ALIASES
PATCHES=[
 (0x1079a2b8,'f1ee087a','f2ee047a','wheel target maximum 6.0 -> 10.0'),
 (0x107992f0,'efeece40',struct.pack('<f',10.4666667).hex(),'follow upper 9.4667'),
 (0x10799328,'efeece40',struct.pack('<f',10.4666667).hex(),'spring upper 9.4667'),
]
