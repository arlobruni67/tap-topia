# Inlines ShopkeeperAnimator.client.lua into ShopStall_CommandBar.lua.
# Studio's Command Bar can't parse multi-line [[long strings]], so the
# source is embedded as a table of one-line strings. Run after editing
# the animator: python3 shop-stall/build.py
import pathlib

here = pathlib.Path(__file__).parent
src = (here / "ShopkeeperAnimator.client.lua").read_text().rstrip("\n").split("\n")


def q(line):
    return '"' + line.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t") + '"'


block = "local ANIM_SOURCE = table.concat({\n" + "".join(f"\t{q(l)},\n" for l in src) + '}, "\\n")\n'

p = here / "ShopStall_CommandBar.lua"
lines = p.read_text().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("local ANIM_SOURCE = "))
end = next(i for i in range(start, len(lines)) if lines[i].startswith("}, ") or lines[i] == "]==]")
lines[start : end + 1] = block.rstrip("\n").split("\n")
p.write_text("\n".join(lines))
