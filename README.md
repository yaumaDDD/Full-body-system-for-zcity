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
  (10 файлов), `addon.json`, `README.md` и `SOURCE_INDEX.md`. Копируется одной
  папкой в `garrysmod/addons/`.

## Исправления этой сборки

* Мини-игры бинтования и шприца теперь **на весь экран**: runtime-патч
  `WoundSystem.MinigameClip.GetRect()` + пересчёт board/оффсетов
  (`zc_woundsystem_compat_fullscreen_minigame 0` — откат).
* Убрана надпись «Not completed - nothing was applied» при закрытии мини-игры
  без дозы (`zc_woundsystem_compat_hide_empty_notice 0` — вернуть).
* Исправлен «адреналиновый» FOV-взрыв: C:U `0..100` → ZCity `0..2`,
  `painkiller` → `0..1`, плюс клиентский кламп.
* Кровотечение больше не размазывается по всем 15 лимбам: берутся реальные
  `org.wounds` / `org.arterialwounds` по костям.
* Шрапнель от дробовика снова появляется: учитываются `took=false` (ZCity
  пересылает хит в `FakeRagdoll`) и `DMG_GENERIC` у патронов `12/70 gauge`,
  у которых `dmgtype` закомментирован в `sh_ammostuff.lua`.
* **Все экранные эффекты C:U отключены** — остаются только эффекты ZCity:
  сняты `RenderScreenspaceEffects` (шейдеры боли, блюр, туннель, аберрация),
  статик/виньетки, moodles, self-talk, death screen, `CalcView`-тряска,
  aim-kick, unconscious eye view, туман, искажение текста и звуковой слой
  (музыка, тиннитус, HEV, искажение чата). Панель ран,
  mini-игры и курсор C:U сохранены (`zc_woundsystem_compat_disable_cu_fx 0` — откат).
* **Кровь C:U убрана**: декоративные брызги/лужи/следы, «alien»-кровь на
  моделях и подавление ванильной крови (`woundsys_replace_vanilla_blood`)
  отключены, поэтому снова работает кровь ZCity / Hemogen
  (`zc_woundsystem_compat_disable_cu_blood 0` — откат).
* В мини-игре бинтования/шприца **персонаж больше не ходит, а курсор появляется**:
  клиентский + серверный `SetupMove` обнуляют движение/поворот/кнопки,
  `PlayerBindPress` глушит бинды ZCity, а `WoundSystemIsAnyWoundMinigameActive`
  расширен, чтобы C:U watchdog не крал курсор. **Камера тоже заморожена** —
  `InputMouseApply`/`CreateMove`/`SetupMove` возвращают `ViewAngles`, сохранённые
  при открытии (обнуление одного `MouseX/Y` не работало: GMod применяет мышь
  раньше `SetupMove`).
* **Шрапнель только от дробовика и взрыва**: старый тест принимал любой
  `DMG_BULLET` и даже патрон «9x19 mm» — из-за неё осколки лезли от пистолетов.
  Теперь определяется по `DMG_BUCKSHOT`, калибрам `12/70`, `20/70`, `23x75` и
  `NumBullet > 1` у shotgun-SWEP; взрыв даёт фрагменты по `DMG_BLAST`.
  Откат: `zc_woundsystem_compat_shrapnel_only_shotgun_blast 0`.
* **Шрапнель ложится в раненую конечность**: конечность берётся из
  `org.dmgstack[hitgroup]` / `ply.HitBones` (авторитетные данные ZCity), а не из
  «ближайшей кости» по точке входа пули. Если конечность не определена —
  осколок не создаётся вообще, чтобы не появляться «непонятно где».
* **`reset organism` больше не поднимает персонажа**: `WB.ResetOrganism` явно
  звал `RestoreRagdoll` → `hg.FakeUp`, а `hg.organism.Clear` сбрасывал
  `otrub/fake/canmove`. Теперь состояние без сознания / fake-ragdoll
  сохраняется, структура `ply.organism` ZCity не подменяется; обычный спавн
  очищается как раньше (`zc_woundsystem_compat_preserve_reset_structure 0` — откат).
* **Шрапнель не теряется при падении в ragdoll**: C:U `InitPlayer()` обнуляет
  `PlayerLimbs` на `Fake`/`FakeUp`/спавне, а старый `PullShrapnel` тянул пустую
  таблицу обратно в `ply.organism`. Теперь синхронизация двусторонняя: новая
  таблица limbs → осколки восстанавливаются из организма; та же таблица →
  извлечение в мини-игре честно уменьшает счётчик.
* **Стекло в ragdoll снова регистрируется**: glass-хук вынесен в отдельный
  `Ragdoll Collide`/`WSZC_GlassRagdoll` (раньше висел `pre`-функцией на ZCity
  хуке `organism`), стекло определяется и по surfaceprop, и по браш-сущности,
  порог скорости снижен с 350 до 120, убран фильтр `DeltaTime >= 0.25`,
  владелец ragdoll резолвится и через `NWEntity("ply")`.
* **Осложнения от shrapnel-мини-игры**: C:U `BreakShrapnelGrasp()` добавляет
  `state.bleed`/`state.pain` при рывке, но shadow перезаписывал их из организма
  каждые 0.25 с. Теперь скачок детектируется и уходит в `ply.organism`:
  боль, рана на конечности с осколком и **нарастающее кровотечение** (пока
  осколок не извлечён).
* **Рука в мини-игре шприца снова двигается, курсор не мигает**:
  `InputMouseApply` больше не возвращает `true` (это убивало `gui.MousePos()`),
  `+attack`/`+attack2` пропускаются к UI, курсор удерживается без проверки
  `vgui.CursorVisible()`, а watchdog больше не роняет его между пакетами.

Подробности и таблица причин: [`woundsystem_zcity_compat/SOURCE_INDEX.md`](woundsystem_zcity_compat/SOURCE_INDEX.md)
и раздел «Исправления по скриншотам» в `woundsystem_zcity_compat/README.md`.

Все клавиши и команды ZCity: [`ZCity_binds.md`](ZCity_binds.md) и
[`zcity_binds.cfg`](zcity_binds.cfg).
