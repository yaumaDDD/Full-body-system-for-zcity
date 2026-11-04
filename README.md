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
  статик/виньетки, moodles, self-talk, **визуал экрана смерти** (не сам ввод),
  `CalcView`-тряска, aim-kick, unconscious eye view, туман, искажение текста и
  звуковой слой (музыка, тиннитус, HEV, искажение чата). Панель ран,
  mini-игры и курсор C:U сохранены (`zc_woundsystem_compat_disable_cu_fx 0` — откат).
  Хук `WoundSystem_DeathScreenDisplay` больше **не удаляется**, а оборачивается:
  внутри него живёт единственный обработчик ЛКМ, отправляющий
  `WoundSystem_PlayerRespawnRequest`; без него серверный `WoundSystem_BlockRespawn`
  навсегда запрещал респавн.
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
* **Вывихи вправляются вручную из WoundView**: нативная C:U мини-игра
  `WoundSystemDislocationMinigame` (перетаскивание кости в сустав) подключена к
  кнопке `FIX DISLOCATION`. Истина — ZCity `org.larmdislocation` /
  `org.rarmdislocation` / `org.llegdislocation` / `org.rlegdislocation`:
  вывих не теряется в ragdoll, успешное вправление снимает флаг всей группы,
  добавляет `org.painadd` и не откатывается 4 Гц «тенью». На время сессии
  камера/движение зафиксированы, а `avgPain` ограничен, иначе C:U блокировала
  каждый удар по кости при боли > 75.
* **Переломы остаются «как в ZCity»**: C:U только рисует иконку `state.broken`
  в WoundView по `org.larm/rarm/lleg/rleg >= 1` и `org.brokenribs > 0`.
  Отдельной мини-игры, своей симуляции костей и своих таймеров нет — создание,
  регенерация и лечение идут ванильными `sv_bone.lua` / `sv_pain.lua` и
  медицинскими SWEP'ами ZCity.
* **Инвентарь C:U убран из WoundView**: 5 слотов `1..5`, drag&drop, подбор
  мировых медпредметов (`E`/`F`) и tooltips слотов отключены; скрытый
  виртуальный слот `6` для мини-игр от ZCity SWEP'ов сохранён. Бинды слотов
  остаются за ZCity. Откат: `zc_woundsystem_compat_hide_cu_inventory 0`.
* **Панель UNI-HEALTH («unit») убрана**: левый сканер `UNI-HEALTH v2.03`
  внутри окна осмотра больше не рисуется; сам WoundView, кукла, иконки лимбов,
  кнопки `FIX DISLOCATION` / `REMOVE SHRAPNEL`, tooltips и курсор сохранены.
  Откат: `zc_woundsystem_compat_hide_unit_panel 0`.

* **Повторные live-скриншоты: скрытие доведено до реального рантайма.**
  Прежний фильтр писал обёртку хука прямо в таблицу `hook.GetTable()` (на
  части сборок это копия) и не перехватывал `surface.DrawOutlinedRect` — поэтому
  рамки слотов и `UNI-HEALTH` оставались видны. Теперь замена идёт через
  `hook.Add("HUDPaint", "WoundDollAndPanel", ...)`, дополнительно глушатся
  `DrawOutlinedRect` и `draw.RoundedBox`. Если хук C:U переименован/отсутствует,
  включается запасной контур `PreDrawHUD`/`PostDrawHUD` на весь кадр HUD
  (только в этом случае, чтобы не задевать HUD ZCity). Геометрия зон читает
  `woundsys_ui_scale`, поэтому скрытие не «съезжает» при изменённом масштабе
  интерфейса.
* **Предметы в руках больше не торчат из мини-игры**: на время любой мини-игры
  C:U/WSZC скрывается viewmodel и руки игрока (`PreDrawViewModel`,
  `PreDrawPlayerHands`, `SetNoDraw` на viewmodel), а WoundView не рисуется
  поверх оверлея — раньше кукла и надпись `FIX DISLOCATION` наслаивались на
  кость, из-за чего казалось, что «вправлений много и они слишком высоко».
* **Размер и доступность вправления**: full-screen `Clip.GetRect()` теперь
  применяется **только** к нашим бинту/шприцу; нативные `dislocation` /
  `shrapnel` C:U получают исходный квадрат 760 px, уменьшенный конваром
  `zc_woundsystem_compat_native_minigame_zoom 0.75`. Стартовое смещение кости
  снижено со 100 до `zc_woundsystem_compat_dislocation_start 35`: кость
  остаётся на экране, досягаема курсором и вправляется за короткое
  перетаскивание, а не за десятки ударов. `avgPain` ограничен 60 всё время,
  пока вывих существует (раньше только во время сессии), иначе C:U блокировала
  первый же удар при боли > 75.
* **Рука и курсор**: pain-shake из `sh_handphysics.lua` (`shakeX 120` /
  `shakeY 40`) обнулён в обеих наших мини-играх, максимальный шаг пружины
  ограничен, а спрайт руки 512×1260 уменьшен конваром
  `zc_woundsystem_compat_hand_cursor_scale 0.45`. Нативные мини-игры C:U
  теперь тоже входят в `WSZC.MinigameActive()`: курсор удерживается, камера и
  движение зафиксированы и в dislocation/shrapnel.
* **Перед проверкой**: распакуйте именно этот `zcity_full_pack.zip` (или
  `woundsystem_zcity_compat.zip` поверх него) и **перезапустите клиент и
  сервер** — Lua-обёртки хуков не подхватываются «на горячую» сменой ZIP.

* **Остатки зелёного HUD слева убраны**: после предыдущего релиза фон и текст
  сканера исчезли, но зелёные полосы, лёгкие, бицепс и ЭКГ оставались — C:U
  рисует их `surface.DrawTexturedRectUV` (`DrawRectUVInt`),
  `surface.DrawLine` (ЭКГ) и `surface.DrawPoly` (дуги), а фильтр перехватывал
  только залитые прямоугольники и текст. Теперь обёрнуты и эти три примитива:
  скрывается всё, что попадает в зону сканера/слотов, а кукла, иконки лимбов и
  `FIX DISLOCATION` / `REMOVE SHRAPNEL` по-прежнему рисуются.
* **Респавн после смерти работает**: причина «кильнулся и не смог
  зареспавниться» — удалённый вместе с C:U-эффектами хук
  `WoundSystem_DeathScreenDisplay`. В `cl_health_gui.lua:5716` именно он по ЛКМ
  шлёт `WoundSystem_PlayerRespawnRequest`, а `sv_deathscreen.lua` держит
  `WoundSys_CanRespawn=false`, пока сообщение не придёт. Теперь хук обёрнут
  (`WSZC.WrapCUDeathScreen()`): вся его отрисовка гасится флагом
  `WSZC.CUDeathVisualsHidden`, а логика клика, `clickDebounce`, снятие курсора и
  отправка запроса остаются. Есть независимый запасной обработчик
  `WSZC_CUDeathRespawnFallback` (сработает, если C:U переименует хук): через 1 с
  после смерти ЛКМ отправляет тот же запрос. Дополнительно
  `WSZC.MinigameContextOK()` запрещает считать мёртвого игрока «в мини-игре»,
  `PlayerDeath`/`PlayerSpawn` сбрасывают все `MG.active`, а серверный
  `WSZC_MinigameServerLock` не блокирует `SetupMove` мёртвого игрока — иначе
  залипшая сессия держала курсор, заморозку камеры и запрет биндов вечно.

* **Кукла персонажа и рука переделаны по архиву из репозитория**: в
  `origin/main:для переделывания интерфейса.zip` лежат 15 прозрачных слоёв
  `zcity_delta/unitmenu/limbs/*.png` (уже спозиционированный силуэт), три
  иконки `status/{bleeding,dislocation,fracture}.png` и 9 кадров руки
  `homigrad/handanim/*.png`. Раньше ни один Lua-файл их не использовал. Теперь
  `tools/build_unitmenu_materials.py` нарезает слои в
  `materials/wszc/unitmenu/`, а компат в рантайме находит приватную таблицу
  `Limbs` хука `WoundDollAndPanel` через `debug.getupvalue` и меняет ТОЛЬКО
  визуал: чёрный силуэт + белый контур, свои `ox/oy/size/sourceW/sourceH`.
  Hitbox'ы лимбов, выбор мышью, иконки статусов, `FIX DISLOCATION` и
  `REMOVE SHRAPNEL` остаются родными C:U; иконки перелома/вывиха/крови берутся
  из архива. Рука в бинте/шприце и в нативных мини-играх C:U —
  `handanim/hand.png` (ладонь) и `3_3.png` (кулак) вместо спрайта 512×1260,
  с pivot у кончиков пальцев и без поворота на 290°. Конвары:
  `zc_woundsystem_compat_unitmenu_doll 1`,
  `zc_woundsystem_compat_unitmenu_scale 0.24`,
  `zc_woundsystem_compat_handanim 1`,
  `zc_woundsystem_compat_handanim_scale 0.55`. Исходные ZIP-аддоны не
  правятся; кадры `homigrad/handanim` теперь тоже лежат в самом коннекторе,
  поэтому WIP-аддон и чужие файлы больше не нужны. Если сборка GMod закрывает
  `debug.getupvalue`, остаётся родная кукла C:U: логика WoundView, мини-игр и
  респавна в любом случае не меняется.

* **Все материалы UI теперь внутри сборки — перекидывать ничего не нужно.**
  Исходный `casualites unknown.zip` содержит только Lua (71 файл) и **вообще не
  имеет `materials/`**, поэтому WoundView, сканер, иконки предметов, лимбы
  `middle/*` / `outlines/*` и мини-игры рисовались ERROR-текстурами. Добавленный
  архив `для того чтобы все работало вместе материалы для UI.zip` (362 файла:
  весь `casunknown-images/*`, `woundsystem/*`, `.vtf/.vmt`) вместе с кадрами из
  первого архива (216 PNG) теперь распакован `tools/pack_ui_materials.py` в
  `woundsystem_zcity_compat/materials/` — **647 файлов**, и тем же скриптом
  сборки продублирован в `casualties_unknown_health_system_beta/materials/`
  внутри full pack. Упаковщик сам читает оба архива из `origin/main`, сверяет
  все 125 путей материалов, на которые ссылается C:U/WSZC Lua, и создаёт 36
  недостающих алиасов: 25 с точным регистром (в архиве имена в lowercase, а Lua
  просит camelCase — на Linux-клиенте это ERROR) и 11 переносов спрайтов руки/
  фона в папки `dislocationminigame`, `shrapnelminigame`, `syringeminigame`
  плюс `hemothoraxfill_red`. Итог проверяется assert'ом: ни одного
  неразрешённого материала. Полный список с хэшами — `MATERIALS.sha256`.

### По live-скриншотам: кукла, фильтр HUD, осколки от стекла

Кукла из `unitmenu` шире родного квадрата C:U (760 px). `HiddenRegion()` —
фильтр, который убирает зелёный сканер слева и 5 слотов инвентаря — гасил
**любой** примитив в этих зонах, поэтому на скриншоте у куклы не было левой
руки и нижней части ног, а иконки осколков и `REMOVE SHRAPNEL` /
`FIX DISLOCATION` не рисовались. Исправлено:

* `WSZC.InstallMaterialTracker()` оборачивает `surface.SetMaterial` (C:U
  `SetGuiMaterial()` зовёт его напрямую) и запоминает текущий материал в
  `WSZC._DrawMaterialName`. Устанавливается **всегда**, обоими Think-хуками,
  даже при выключенных `hide_*` конварах.
* `WSZC.IsDollDrawMaterial()` пропускает через фильтр лимбы
  (`wszc/unitmenu/limbs/*`, родные `casunknown-images/middle|outlines/*`),
  иконки статусов (`wszc/unitmenu/status/*`, `casunknown-images/icons/*`) и
  `screen/uiPoint`. Всё остальное — сканер, `UNI-HEALTH`, слоты — по-прежнему
  скрыто; `WSZC.CUDeathVisualsHidden` по-прежнему гасит весь экран смерти.
* Размер куклы по умолчанию уменьшен `0.28 → 0.24`
  (`zc_woundsystem_compat_unitmenu_scale`), чтобы она не заходила в зоны
  слотов даже без трекера.
* Нативный оверрайд руки теперь работает через тот же общий трекер
  (`WSZC._OnSetMaterial`), без второго перехвата `surface.SetMaterial`.

**Осколки от ударов кулаками по стеклу.** Кулаки ZCity
(`weapon_hands_sh.lua:1653`) бьют браш `func_breakable_surf` через
`TakeDamageInfo`, но `PostEntityTakeDamage` для браш-сущностей приходит не на
всех сборках. Добавлен независимый `hook.Add("EntityTakeDamage",
"WSZC_GlassStrikePre", ...)` с общей функцией `WSZC.TryGlassStrike()`;
`return nil` никогда не блокирует ванильный урон, а 0.5-секундный
`glassCooldown` убирает дубли, если сработали оба хука. Резолвинг игрока
ослаблен: у SWEP-кулаков нет `.organism`, поэтому теперь пробуются
`OwnerOf(striker) or OwnerOf(attacker) or OwnerOf(inflictor)`. Путь не зависит
от `zc_woundsystem_compat_shrapnel_only_shotgun_blast` (тот фильтрует только
пули/дробь). Диагностика: `zc_woundsystem_compat_organism_debug 1` → в консоль
`[ZCity/CU compat] glass strike: ent=... ply=... limb=...`. Обязательные
конвары: `zc_woundsystem_compat_shrapnel 1`,
`zc_woundsystem_compat_glass_shrapnel 1`, `zc_woundsystem_compat_authority 1`.

**Кровь hemogen не трогалась.** `project hemogen blood.zip` содержит 123 файла
(`lua/` + `data_static/`) и **не содержит `materials/`**: аддон ссылается на
`advancedblood/sprites/*` и `advancedblood/decals/*`, которых нет ни в одном
архиве репозитория. Розово-чёрные квадраты на скриншоте — это ERROR-текстуры
самого hemogen, а не компата. Ни один файл аддона, ни один его хук или конвар
этой сборкой не изменён; compat к `advancedblood/*` не обращается. Чтобы их
убрать, нужно либо докачать материалы hemogen (отдельный архив/Workshop),
либо отключить аддон — скажите, какой вариант, и сделаю точечно, не трогая
остальное.

Подробности и таблица причин: [`woundsystem_zcity_compat/SOURCE_INDEX.md`](woundsystem_zcity_compat/SOURCE_INDEX.md)
и раздел «Исправления по скриншотам» в `woundsystem_zcity_compat/README.md`.

Все клавиши и команды ZCity: [`ZCity_binds.md`](ZCity_binds.md) и
[`zcity_binds.cfg`](zcity_binds.cfg).
