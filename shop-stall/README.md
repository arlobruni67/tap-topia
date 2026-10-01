# Shop Stall

Replaces your current shop with a blue/white striped market stall and an
animated shopkeeper NPC (asset `11330911907`).

**Files**
- `ShopStall_CommandBar.lua`: paste into Studio's Command Bar.

**Steps**
1. Select your current shop model in the Explorer.
2. Studio → View → Command Bar → paste the script → Enter.
3. Read the Output, then Save/Publish.

**What you get**
- The stall is built where the old shop stood and keeps its name. The old
  shop's ProximityPrompts/ClickDetectors move onto the new counter, and the
  old shop is kept in `ServerStorage` as `<name>_OldShopBackup`.
- The shopkeeper animates on each player's device. It breathes, glances
  around and wipes the counter when it's alone. It waves and says hi when
  a player walks up, then leans on the counter and follows them with its
  head. It nods and opens its arms when the shop prompt is used. Movement
  uses springs, so motion eases in and settles naturally.
- Edit `SIGN_TEXT`, `NPC_ID` at the top of the script, and the greeting lines
  inside it (`GREETINGS`, `PROMPT_LINES`).
- If the stall faces the wrong way, rotate the model with the Rotate tool.
  To rebuild, run the script again with the stall selected.
