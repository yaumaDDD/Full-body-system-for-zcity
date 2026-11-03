# Full-body-system-for-zcity

## Compatibility addon

`woundsystem_zcity_compat/` — отдельный GMod-аддон, который включает существующий
мост из `zcity.zip` с приложенной версией `casualites unknown.zip` без правки
исходных ZIP-архивов.

Аддон поднимает настоящие bandage/syringe мини-игры C:U только для бинтов и непрерывных
шприцевых препаратов (`weapon_bandage_sh`, `weapon_bigbandage_sh`, `weapon_morphine`,
`weapon_fentanyl`, режим `1` медкита). One-dose предметы остаются мгновенными, даже если у них
есть `spec.mg`: `weapon_naloxone`, `weapon_needle`, `weapon_adrenaline`, `weapon_betablock`,
`weapon_mannitol`, `weapon_thiamine`, режимы `2/3/5` медкита. Жгут, обезболивающее,
режим `4` медкита, blood bag и прочие спецы без `mg` тоже остаются мгновенными.

Подробности установки, таблица предметов, конвары и ограничения: [`woundsystem_zcity_compat/README.md`](woundsystem_zcity_compat/README.md).
