# Full-body-system-for-zcity

## Compatibility addon

`woundsystem_zcity_compat/` — отдельный GMod-аддон, который включает существующий
мост из `zcity.zip` с приложенной версией `casualites unknown.zip` без правки
исходных ZIP-архивов.

Аддон также поднимает настоящие bandage/syringe мини-игры C:U для тех ZCity-предметов,
у которых в `WB.SwepSpecs` / `WB.MedkitModes` есть `spec.mg` (то есть предмет по логике ZCity
не применяется мгновенно). Мгновенные предметы — жгут, обезболивающее, режим жгута медкита,
blood bag и т.п. — остаются мгновенными.

Подробности установки, таблица предметов, конвары и ограничения: [`woundsystem_zcity_compat/README.md`](woundsystem_zcity_compat/README.md).
