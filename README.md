# Full-body-system-for-zcity

## Compatibility addon

`woundsystem_zcity_compat/` — отдельный GMod-аддон, который соединяет стандартную
систему здоровья ZCity (`ply.organism`) с приложенной версией
`casualites unknown.zip` без правки исходных ZIP-архивов.

**По умолчанию `ply.organism` авторитетен** (`zc_woundsystem_compat_authority 1`):
здоровье, Organs+, боль/шок/кровотечение, броня, ragdoll и смерть считает ZCity,
а C:U остаётся UI, мини-играми, показателями-«тенью» и протоколом шрапнели.
`zc_woundsystem_compat_authority 0` возвращает прежний мост, где C:U полностью
владела ранами.

Шрапнель — единое поле `state.shrapnel` без признака источника и без второй
мини-игры: пули, взрывы и **стекло** (руки/ноги, ragdoll-коллизии) пишут один
счётчик, а родная кнопка `REMOVE SHRAPNEL` в панели C:U открывает тот же
`BuildShrapnelSession()`.

В круговом селекторе ZCity добавлена кнопка «Проверить травмы»: она открывает
родную панель осмотра C:U (`WoundSystem.OpenHealthHUD`), а не новый интерфейс.
Штатный пункт ZCity `Examine Body` перехватывается и переименовывается, дубля
нет. Панель C:U показывает состояние `LocalPlayer()`, поэтому кнопка проверяет
себя; осмотр другого игрока в этой панели не предусмотрен.

Настоящие bandage/syringe мини-игры C:U поднимаются только для бинтов и
непрерывных шприцевых препаратов (`weapon_bandage_sh`, `weapon_bigbandage_sh`,
`weapon_morphine`, `weapon_fentanyl`, режим `1` медкита). One-dose предметы
остаются мгновенными, даже если у них есть `spec.mg`: `weapon_naloxone`,
`weapon_needle`, `weapon_adrenaline`, `weapon_betablock`, `weapon_mannitol`,
`weapon_thiamine`, режимы `2/3/5` медкита. Жгут, обезболивающее, режим `4`
медкита, blood bag и прочие спецы без `mg` тоже остаются мгновенными.

Подробности установки (включая список подписок Мастерской и обязательный
`Simple Custom Shaders`), таблица источников шрапнели, таблица предметов,
конвары и ограничения: [`woundsystem_zcity_compat/README.md`](woundsystem_zcity_compat/README.md).

## Готовые архивы

* **`zcity_full_pack.zip`** — пересобранный полный пакет: распакованная структура
  `garrysmod/addons/` со всеми аддонами (ZCity, C:U, Organs+, Hemogen, Eye Gore,
  Gore V2, WIP-текстуры интерфейса) и коннектором, плюс `garrysmod/cfg/zcity_binds.cfg`,
  `README_INSTALL.md`, `WORKSHOP_IDS.txt`, `ZCity_binds.md`, `MANIFEST.txt`.
* **`woundsystem_zcity_compat.zip`** — только аддон-коннектор **с исходным Lua-кодом**
  (8 файлов), `addon.json`, `README.md` и `SOURCE_INDEX.md`. Копируется одной
  папкой в `garrysmod/addons/`.

Все клавиши и команды ZCity: [`ZCity_binds.md`](ZCity_binds.md) и
[`zcity_binds.cfg`](zcity_binds.cfg).
