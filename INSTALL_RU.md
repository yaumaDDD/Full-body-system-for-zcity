# ZCity — полный пакет (ZCity + все «примочки» + коннектор)

Один архив `zcity_full_pack.zip` с уже распакованной структурой `garrysmod/`.
Никакие исходные ZIP-аддоны не перепаковывались «внутрь z_city»: каждый аддон
лежит своей папкой в `garrysmod/addons/`, как и требует GMod. Сливать их в один
аддон нельзя — совпадут пути `lua/autorun/*`, `addon.json` и порядок загрузки,
что даёт ошибки и дубли хуков.

## Состав

| Папка в `garrysmod/addons/` | Источник | Роль |
|---|---|---|
| `z_city/` | `zcity.zip` | Гейммод ZCity, база: `ply.organism`, оружие, инвентарь, режимы |
| `casualties_unknown_health_system_beta/` | `casualites unknown.zip` | C:U: панель ран, мини-игры, шрапнель, «теневые» метрики |
| `z_city_organs_plus/` | `zcity organs +.zip` | Organs+: дополнительные органы (через `hg.organism`) |
| `project_hemogen_zcity/` | `project hemogen blood.zip` | Кровь/эффекты Hemogen |
| `simple_eye_gore/` | `simple eye gore.zip` | Повреждение глаз у ragdoll (не зависит от ZCity) |
| `zсity_gore_v2/` | `zcitygore.zip` | Gore V2: модели, звуки, ампутации. **В имени кириллическая «с»** — оставлено как в оригинале |
| `human_hands_for_z_city_casualties_medical_system_heavy_wip/` | `для переделывания интерфейса.zip` (ветка `main`) | WIP-текстуры интерфейса (только PNG/JPG). `addon.json` добавлен при сборке |
| `woundsystem_zcity_compat/` | исходный код из репозитория | Коннектор: `ply.organism` авторитетен, C:U = UI/мини-игры/shrapnel |

Дополнительно в корне архива: `ZCity_binds.md`, `WORKSHOP_IDS.txt`,
`MANIFEST.txt`; в `garrysmod/cfg/` — `zcity_binds.cfg`.

> В сборке `z_city/` убрана одна строка `sv_woundbridge.lua` — надпись
> «Not completed - nothing was applied». В коннекторе есть такой же
> рантайм-фильтр, поэтому при установке аддона на стоковый ZCity правка
> исходника не требуется (`zc_woundsystem_compat_hide_empty_notice 0` вернёт
> надпись).

### Что исправлено по скриншотам

| Что | Конвар по умолчанию |
|---|---|
| Мини-игры бинта/шприца на весь экран | `zc_woundsystem_compat_fullscreen_minigame 1`, размер — `zc_woundsystem_compat_minigame_zoom 0.85` |
| Нет надписи «Not completed - nothing was applied» | `zc_woundsystem_compat_hide_empty_notice 1` |
| Нет «адреналинового» FOV-взрыва и радиальных полос | `zc_woundsystem_compat_clamp_adrenaline 1` |
| Кровотечение только на раненых лимбах | `zc_woundsystem_compat_limb_bleed 1` |
| Бинт лечит обычные раны и показывает прогресс | Вместе с `zc_woundsystem_compat_minigames 1`: уменьшается severity только `org.wounds`; `STOP N%` и кольцо показывают фактически остановленную долю обычного кровотечения, повторная перевязка разрешена до 100% |
| Артерия останавливается только жгутом | Бинт не трогает `org.arterialwounds` / artery-флаг и не тратится при artery-only ране. Жгут через `WB.SwepHeal → H.ApplyItemToBody` использует прицельную конечность также при self-use, реально удаляет её артериальную рану и ставит `Tourniquets` на ту же кость; synthetic wounds содержат валидные `Vector`/`Angle` для native renderer |
| Ампутация оставляет видимую культю и отдельный статус | Native `forearm + hand` / `crus + foot` скрыты, proximal `arm/thigh` остаются. `WSZC_AMPUTATION` не удаляет arterial wound и рисуется раньше bleed/tourniquet; кровоточащая культя имеет приоритет для жгута, distal aim перенаправляется на неё |
| Шрапнель от дробовика/взрыва | `zc_woundsystem_compat_shrapnel 1`, `zc_woundsystem_compat_shrapnel_on_blocked 1` |
| Только эффекты ZCity: все эффекты C:U выключены | `zc_woundsystem_compat_disable_cu_fx 1` |
| Кровь C:U убрана, ванильная кровь ZCity/Hemogen возвращена | `zc_woundsystem_compat_disable_cu_blood 1` |
| В мини-игре персонаж не ходит, не крутит камерой и виден курсор | включается вместе с `zc_woundsystem_compat_minigames 1` (без отдельного конвара) |
| Шрапнель только от дробовика и взрыва, не от пистолетов | `zc_woundsystem_compat_shrapnel_only_shotgun_blast 1` |
| Дробовик/взрыв оставляют осколки в фактически раненой части (`org.dmgstack` / `HitBones`), не только в кистях/стопах; стекло отдельно сохраняет правило `hand_L/R` / `foot_L/R` | включается вместе с `zc_woundsystem_compat_shrapnel 1` |
| `reset organism` не поднимает персонажа, сохраняет down-структуру и полностью очищает раны/шрапнель/инфекцию/повязки/жгуты/C:U residue и красный перелом рёбер | `zc_woundsystem_compat_preserve_reset_structure 1`; дополнительно очищается забытое native-кодом поле `org.brokenribs`. Внутренний FakeUp (`OverrideSpawn`) сохраняет весь organism, включая wounds/arteries/ампутации/переломы/third-party поля, а настоящий respawn очищает его |
| Шрапнель сохраняется при падении/подъёме из ragdoll | включается вместе с `zc_woundsystem_compat_shrapnel 1` |
| Стекло в ragdoll (руки/ноги) даёт осколки | `zc_woundsystem_compat_glass_shrapnel 1` |
| Ошибки в shrapnel-мини-игре → боль и нарастающее кровотечение | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Рука/курсор работают в мини-игре шприца | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Вывихи вправляются вручную (`FIX DISLOCATION` в WoundView), состояние в `ply.organism` | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Переломы видны в WoundView, но считаются/лечатся ZCity (`sv_bone.lua`) | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Инвентарь C:U скрыт и при самоосмотре, и в чужом WoundView; виртуальный слот `6` для ZCity SWEP'ов остаётся | `zc_woundsystem_compat_hide_cu_inventory 1`; remote treatment не делает исключения. Расходуемые предметы применяются штатными ZCity SWEP на пациента |
| Лечение другого игрока в том же WoundView | Отдельная «Лечить игрока» при наведении на пациента; те же 17 зон/neck/pelvis, без отдельного HUD. Самоосмотр не изменён. `zc_woundsystem_compat_remote_inspect_button 1` |
| Панель `UNI-HEALTH` / unit внутри WoundView скрыта | `zc_woundsystem_compat_hide_unit_panel 1` |
| Рамки слотов и `UNI-HEALTH` скрыты и при нестандартном масштабе UI | `zc_woundsystem_compat_hide_cu_inventory 1`, `zc_woundsystem_compat_hide_unit_panel 1` (фильтр через `hook.Add`; `PreDrawHUD` — запасной контур) |
| Предмет / viewmodel в руках скрыт в мини-игре | включается вместе с `zc_woundsystem_compat_minigames 1` |
| WoundView не наслаивается поверх мини-игры | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Нативная мини-игра вправления меньше исходного квадрата C:U | `zc_woundsystem_compat_native_minigame_zoom 0.85` (диапазон `0.4..1.2`) |
| Кость вправления рядом с суставом и на экране | `zc_woundsystem_compat_dislocation_start 35` (диапазон `10..100`) |
| Компактная рука одного размера во всех мини-играх | `zc_woundsystem_compat_hand_cursor_scale 0.55`, `..._handanim_scale 1`; единый множитель в C:U/WSZC, миграция revision 6, hitbox/центр/rotation не меняются |
| Кукла WoundView собрана из 17 пиксельно трассированных интерактивных частей чистого `1435.png` + иконки статусов | `zc_woundsystem_compat_unitmenu_doll 1`, `zc_woundsystem_compat_unitmenu_scale 0.25`; полный black/white POT round-trip = 0 различий, native `woundsys_ui_scale` компенсируется (диапазон `0.1..0.8`) |
| Отдельная шея: hitbox/hover, `Broken neck`, подсказка Skin/Muscle и синхронизация на первой жизни | `org.skull`, `Bip01_Neck1` и `neckartery` относятся к `PlayerLimbs.neck`; head не дублирует перелом. Подсказка: `Neck / Skin: N% / Muscle: N%`; ZCity HUD, таймер и нижние слоты сохранены |
| Живот и таз — отдельные native части | `abdomen` выше шва `y=520`, `pelvis` ниже; у каждого свой sprite/hitbox/hover/action/net state. `Spine1/Stomach` → abdomen, `Pelvis/Hips` → pelvis. Бинт лечит только выбранную рану; общий `org.pelvis` не дублируется |
| Все 653 UI-материала внутри сборки (без ERROR и ручного копирования) | `woundsystem_zcity_compat/materials/` + зеркало в `casualties_unknown_health_system_beta/materials/`, генератор `tools/pack_ui_materials.py` |
| Человеческая рука C:U в мини-играх — ладонь/кулак 512×1260 | `zc_woundsystem_compat_handanim 1`, `..._hide_minigame_hand 0`, общий размер `..._hand_cursor_scale 0.55`; спрайты `wszc/minigame/hand_idle.png` / `hand_click.png` |
| Зелёные полосы/лёгкие/ЭКГ сканера слева скрыты | `zc_woundsystem_compat_hide_unit_panel 1` (глушатся `DrawTexturedRectUV`, `DrawLine`, `DrawPoly`) |
| Экран смерти C:U не рисуется, но ЛКМ респавнит | включается вместе с `zc_woundsystem_compat_disable_cu_fx 1`; хук обёрнут, а не удалён |
| Кукла не обрезается слева/снизу, видны `REMOVE SHRAPNEL` и `FIX DISLOCATION` | `WSZC.InstallMaterialTracker()` + `WSZC.IsDollDrawMaterial()`; размер `zc_woundsystem_compat_unitmenu_scale 0.25` |
| Осколки от ударов кулаками по стеклу | `zc_woundsystem_compat_shrapnel 1`, `zc_woundsystem_compat_glass_shrapnel 1`, резервный хук `WSZC_GlassStrikePre` на `EntityTakeDamage`; диагностика `zc_woundsystem_compat_organism_debug 1` |
| Кровь `project hemogen blood` не изменена | compat не обращается к `advancedblood/*`; ERROR-квадраты — отсутствующие материалы самого аддона |
| WSZC мини-игры на весь экран; нативные C:U — умеренно отдалены | `zc_woundsystem_compat_fullscreen_minigame 1`, `zc_woundsystem_compat_fullscreen_native 0`, `zc_woundsystem_compat_native_minigame_zoom 0.85`. Растяжение нативных игр давало огромный обрезанный осколок и уводило нижнюю часть раны за экран |
| Нет белых пустых слотов и чёрной подложки поверх куклы | `HiddenRegionRaw()` для `DrawOutlinedRect`/`DrawRect`/`RoundedBox`/`DrawLine`/`DrawPoly`; whitelist только для текстур и текста |
| После «Reset organism» снова можно быстро бегать | `RESET_KEEP` больше не несёт `canmove/stun/consciousness/brain`; `WSZC.ClearMovementPenalties()` снимает штрафы движения во всех трёх путях ресета |
| Кукла повторяет чистый зелёный эталон `1435.png`, включая обводку и расстановку | `tools/build_unitmenu_materials.py`: SHA-pinned clean reference, 17 независимых анатомических масок, **стандартный чёрный `(0,0,0)`** и фактические белые контуры, включая пальцы/подмышки/швы/стопы. Каждый POT sprite проверяется обратным C:U downsample: **0 различающихся black/white пикселей во всех полных cells**, 0 на границах POT, 9 scanlines точно равны 1435. Старый archive-fit — только fallback. `zc_woundsystem_compat_unitmenu_tint 1` ставит белый `SetDrawColor` **только** для `*_fill.png`; `*_edge.png` остаётся под `finalOutline` C:U, hover/hitboxes/dismemberment не изменены |
| Нет ложного `disinfected/processing`, настоящие статусы сохранены | Native `AddHudIcon` пропускает только `Icons.disinfected`; infection/bleed/fracture рисуются штатно, а gameplay `disinfectTime` не обнуляется |
| Повторный бинт не залипает на частичной/закрытой ране | `BestBandageLimb` читает реальные `organism.wounds`/aftercare и игнорирует stale `isBandaged` и shadow-only bleed. После последнего treatment сервер вызывает `completed`, обычный `onClose/AfterUse`, удаляет slot и overlay |
| Лишний текст убран, затемнение фона сохранено во всех мини-играх | `zc_woundsystem_compat_hide_minigame_text 1`: `WSZC.InstallMinigameTextFilter()` обнуляет `title/value/guide/panelAlpha` в `Clip.DrawHeader` (иконка остаётся), глушит `Clip.DrawExitGuide` и **сохраняет `Clip.DrawBackdrop`** (затемнение фона), точечно фильтрует chrome-шрифты (`RetroTooltipTitle*`, `RetroTooltipDesc*`, `RetroMinigameGuide*`) **и AED `WoundSystemAEDStatus`** (только пока мини-игра активна). `minigameshrapnel.png` — передний слой раны, **не удаляется**; все игровые спрайты защищены `WSZC.IsMinigameGameplaySprite()`. Уведомления ZCity, статусные надписи C:U (кроме AED), красный death-текст, капли, `Icons.*`, осколки и рука не трогаются; `0` — вернуть как было |
| Рука мини-игры действительно совпадает с курсором | `zc_woundsystem_compat_hand_pin_cursor 1` (по умолчанию): каждый Think `gui.MousePos()`, `handScreenX/Y`, grab/orbit и видимый pivot синхронизируются; C:U offset `100/400`, spring и collision clamp не сдвигают руку. `0` — прежние HandPhysics, инерция, боль и developer offsets |
| Светлый фон WoundView | `zc_woundsystem_compat_hide_woundview_backdrop 1` гасит полноэкранный `woundbg`/blackout только пока `WoundSystemHealthHUDOpen == true` |
| Положение и захват сохраняют C:U | Canvas `512×1260`, pivot `0.4 / 0.1` и прежний `rot`; визуальные `w/h` умножаются на `0.55`, а центр пересчитывается так, чтобы повёрнутые пальцы оставались на `handScreenX/Y` (или реальном курсоре в pin-режиме). Native hitbox не изменяется отдельно |
| В мини-игре видна рука, системный курсор не мигает | `zc_woundsystem_compat_hide_minigame_cursor 1`; hand draw и watchdog удерживают `blank` без периодического `arrow`, стрелка возвращается на выходе. `..._hide_minigame_hand 1` — arrow-only режим |
| После смерти не «залипают» мини-игры/курсор/лок движения | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Потеря сознания закрывает WSZC и нативные мини-игры, overlay, WoundView, cursor/view/input; conscious ragdoll не закрывает | серверный force-close `WSZC_MinigameForceClose`; проверяется владелец сессии, а не пациент медика. `FakeRagdoll/fake` — posture; death/otrub/NW unconscious/`consciousness < 0.4` — incapacity. FakeUp сохраняет игру, настоящий respawn закрывает её принудительно |
| Любой неизвлечённый fragment наращивает реальную боль и кровотечение | `zc_woundsystem_compat_shrapnel_lodged_effects 1`; последний extracted fragment удаляет tagged-рану/source/irritation |
| Дополнительные WoundView-карточки/polish удалены | Конвара `woundview_polish` больше нет; сохранены прежние откалиброванные позиции/размеры doll и hitboxes, чёрная анатомия, shaped outlines и hover |
| Бинт можно наложить на шрапнель: внешняя кровь останавливается, но закрытый фрагмент заражает рану | Стандартная иконка infection; конечность → торс (240 с) → мозг (420 с) → смерть (600 с). `zc_woundsystem_compat_bandaged_shrapnel_infection 1`, таймер `zc_woundsystem_compat_shrapnel_infection_death_delay 600` |
| Обязательный цикл лечения шрапнели | `REMOVE SHRAPNEL` запускает обратное разматывание на 360° (без click-unwrap и расхода предмета) → нативное извлечение → повторный полный бинт. Только финальный бинт очищает инфекцию. Любое извлечение добавляет отдельную растущую aftercare-рану и медленно растущую боль |
| Физического бинта хватает, обычное кровотечение снижено | `zc_woundsystem_compat_bandage_strength 3`, `zc_woundsystem_compat_bleeding_multiplier 0.55`, tagged shrapnel-рана ограничена severity 8; артерия не ослаблена и требует жгута |
| Расход бинта соответствует ZCity | Namespaced bandage input измеряет реально удалённую `org.wounds` severity и вычитает её из `swep.modeValues[idx]`: severity 4 = 4 заряда для обоих бинтов (40/150). Последняя единица не даёт overheal; пустые/artery-only круги и нулевой aftercare бесплатны. Виртуальный slot получает только авторитетный остаток (старое client-predict `100/12` удалено), а оригинальный `onClose/AfterUse` удаляет исчерпанный предмет без второго `onProgress/Consume` |
| Физический жгут работает даже при отказе/ошибке C:U apply | `weapon_tourniquet → WB.SwepHeal → H.ApplyItemToBody`: сначала лечатся реальные ZCity-раны, затем native status best-effort; расход только по фактически обработанной ране, двойного mirror нет |
| Дробовик определяется у настоящего ZCity PhysBullet | Проверяются attacker active weapon, known/family class, `Primary.Ammo`, ammo name и pellets; `inflictor=attacker`, `DMG_BULLET` и ammo `-1` больше не мешают. Пистолет и bare `DMG_BUCKSHOT` осколков не создают |
| Если респавн не сработал | подождите 1 с после смерти и нажмите ЛКМ; откат визуала C:U — `zc_woundsystem_compat_disable_cu_fx 0` |

Ассеты для куклы и руки берутся из архива `для переделывания интерфейса.zip`
(`origin/main`). Нарезанные PNG лежат в `woundsystem_zcity_compat/materials/wszc/unitmenu/`,
кадры руки — в `.../materials/wszc/minigame/` (исходники `homigrad/handanim` тоже внутри коннектора,
WIP-аддон больше не обязателен), а весь `casunknown-images/*` — рядом с ними и
дублируется в папку C:U. Скрипты пересборки —
`tools/build_unitmenu_materials.py`, `tools/build_minigame_hand.py` и `tools/pack_ui_materials.py`, список с
хэшами — `woundsystem_zcity_compat/MATERIALS.sha256`. Ни один Lua-файл внутри
исходных ZIP-аддонов не изменён.

Панель травм, HUD и протокол шрапнели C:U при этом остаются — отключаются только
визуальные эффекты, декоративная кровь, инвентарь C:U и левый сканер
`UNI-HEALTH`, а не сам WoundView.

## Лечение другого игрока

1. Подойдите к живому игроку или его ragdoll на расстояние до 256 units и
   наведитесь на него.
2. Выберите отдельную **«Лечить игрока»** в радиальном меню. Обычная
   «Проверить травмы» по-прежнему открывает самоосмотр. Для бинда доступна
   команда `wszc_treat_player`.
3. Откроется **тот же WoundView, что при самоосмотре**: те же 17 анатомических
   зон, отдельные `neck/pelvis`, материалы, hitboxes, hover и мини-игры. Нет
   отдельного remote doll, HUD или patient banner.
4. Пять C:U-слотов здесь также скрыты, интерфейс полностью совпадает с
   самоосмотром. Для лечения возьмите медицинский ZCity SWEP и на **обычной
   дистанции прицела SWEP** (не на дистанции осмотра 256) примените ПКМ на
   пациента или его ragdoll: поддержаны все 12 standalone medical SWEP и все
   5 режимов medkit. Заряд расходует **медик**, эффект получает **пациент**;
   continuous bandage/syringe требуют выполнить мини-игру. Для bloodbag `R`
   переключает take/give blood, после чего удерживайте ПКМ на пациенте (ЛКМ —
   на себе). В WoundView доступны native shrapnel/dislocation, снятие statuses
   и возврат жгута. C:U-предметы доступны только если инвентарь намеренно
   включён конваром `zc_woundsystem_compat_hide_cu_inventory 0`.

При remote-снятии `TOURNIQUET` `weapon_tourniquet` возвращается медику, при
self-removal — пациенту. Сохранены advanced 180-секундный lifecycle жгута,
partial bandage, shrapnel aftercare и защита исходных/посторонних/arterial wounds.
Сервер проверяет двух игроков, дистанцию, активную сессию, typed payload и слот
на каждом действии. Смерть, disconnect, выход из дистанции и закрытие панели
прерывают лечение. Remote treatment и его кнопка отключаются конваром
`zc_woundsystem_compat_remote_inspect_button 0`.

## Запуск на другой сборке ZCity

Используйте отдельный `woundsystem_zcity_compat.zip`, а не заменяйте файлы самой
сборки из `zcity_full_pack.zip`. Распакуйте одну папку
`woundsystem_zcity_compat/` в `garrysmod/addons/`: все 653 UI-материала, 3
шрифта и 3 собственных C:U `.vcs` уже внутри неё, отдельно копировать
`resource/`, `shaders/` или `materials/` из C:U не нужно. Установленные ZCity и
C:U всё равно обязательны: connector адаптирует их API, но не содержит
самостоятельную систему здоровья.

По умолчанию включён `zc_woundsystem_compat_adaptive 1`. Он выбирает native API
новой C:U либо legacy adapter приложенной версии, а неподдерживаемые необязательные
функции отключает независимо. После входа на сервер выполните в консоли:

```text
wszc_compat_status
```

Первая строка содержит профиль совместимости, а строки `core/inspection/medicine/
external_minigames/remote/organism_extensions` — фактически доступные функции и
причину отключения. После обновления аддонов без смены карты выполните
`wszc_compat_reprobe`. `zc_woundsystem_compat_prefer_native_api 1` сохраняет
родной external-minigame API новой C:U вместо его замены.

Абсолютно любая сборка не гарантируется: при `profile=partial/unavailable` или
`core=no` пришлите этот вывод и ZIP сборки для отдельного адаптера. Не включайте
`zc_woundsystem_compat_adaptive 0` как обычное «исправление» — это override для
эксперимента и возврата старого blind-patching поведения.

## Установка

1. Распаковать `zcity_full_pack.zip` во временную папку.
2. Скопировать **содержимое** его папки `garrysmod/` в `garrysmod/` сервера
   (папки `addons/` и `cfg/` должны лечь рядом с уже существующими, а не
   вложиться друг в друга).
3. Запустить сервер с гейммодом `zcity` (`+gamemode zcity`).
4. В консоли клиента: `exec zcity_binds.cfg` (или вписать строки в
   `garrysmod/cfg/autoexec.cfg`).
5. В консоли сервера проверить строку:
   `[ZCity/CU compat] compatibility layer active (ply.organism owns health; C:U = HUD, minigames, shrapnel)`.

## Подписки Мастерской (обязательно для контента)

ZCity сам вызывает `resource.AddWorkshop` при `hg_loadcontent 1`:

```text
3657897364  основной контент ZCity
3257937532  distac content
3389728250  Glide
3389795738  GTAV helicopters (Glide)
```

На выделенном сервере эти ID должны быть в коллекции
`+host_workshop_collection <ID>` вместе с `-authkey`, либо в `workshop.vdf`.
Без них клиенты увидят ERROR-модели и `missing material`.

**Про C:U — важное исключение.** В исходном ZIP репозитория лежат Lua, 3
шрифта и 3 шейдера, но нет `materials/` и `sound/`. Теперь коннектор сам
содержит **653 UI-материала + 3 шрифта + 3 собственных C:U `.vcs`**. В full
pack материалы дополнительно зеркалируются в папку C:U, а шрифты/шейдеры
физически перенесены только в коннектор. Пути остаются прежними
(`materials/...`, `resource/fonts/...`, `shaders/fxc/...`), поэтому C:U находит
их через обычный `GAME` search path.

На выделенном сервере коннектор сам регистрирует эти 659 resource paths для
клиентов: `zc_woundsystem_compat_resource_downloads 1` (по умолчанию, после
изменения нужна смена карты/restart). Если контент уже раздаётся вашей
Workshop-коллекцией или отдельным resource-сервером, поставьте `0`. Включать
`woundsys_resource_downloads` ради UI больше не требуется; при включённых обоих
конварах общий `Resources.Added` исключает дубли.

В исходных архивах **нет звуков C:U** — они не подменялись и не выдумывались.
Также `Simple Custom Shaders 3440271589` относится к дополнительным внешним
C:U-эффектам, а не к трём собственным `.vcs`, которые уже перенесены. Выберите
один экземпляр C:U:

* **Вариант А (рекомендуется, точная версия):** оставить папку C:U из пакета и
  коннектор. Для звуков можно добавить **только `sound/`** из отдельного
  контент-пака C:U; вторую копию Lua/GMA при этом не добавлять.
* **Вариант Б:** подписаться на C:U `3728573930` и при необходимости внешних
  эффектов на `Simple Custom Shaders 3440271589`, а папку
  `casualties_unknown_health_system_beta` из пакета **удалить**. Иначе C:U
  загрузится дважды: двойные хуки, таймеры, net-сообщения и HUD.

Вариант Б ставит живую версию из Мастерской, которая обновлялась и может
отличаться от билда, под который написан коннектор. Если `WSZC_Ready`
остался `false` — верните папку из пакета (вариант А).

## Конвары

```text
woundsys_enabled 1                      HUD/мини-игры/shrapnel C:U (не выключать)
zc_woundsystem_bridge 1                 сам мост ZCity
zc_woundsystem_compat_authority 1       ply.organism авторитетен (0 = старый мост)
zc_woundsystem_compat_shrapnel 1        единый state.shrapnel
zc_woundsystem_compat_glass_shrapnel 1  стекло как источник шрапнели
zc_woundsystem_compat_bandage_strength 3  усиление реального treatment budget бинта
zc_woundsystem_compat_bleeding_multiplier 0.55  верхний cap обычного bleedingmul
zc_woundsystem_compat_bandaged_shrapnel_infection 1  инфекция под повязкой
zc_woundsystem_compat_shrapnel_infection_death_delay 600  секунды до fatal brain infection
zc_woundsystem_compat_inspect_button 1  кнопка «Проверить травмы» в радиал-меню
zc_woundsystem_compat_remote_inspect_button 1  кнопка «Лечить игрока» при наведении
zc_woundsystem_compat_resource_downloads 1  отдача UI/materials/fonts/shaders клиентам
zc_woundsystem_compat_debug 1           диагностика коннектора
```

`zcity_gore_torso_workshopid` — если Gore V2 поставлен папкой и не видит свой
Workshop ID, задайте его вручную; при установке из Мастерской он определяется
через `engine.GetAddons()`.

## Известные конфликты клавиш

`Q` (радиал-меню вместо спавн-меню), `F` (фонарь/ЛЦУ + меню вины + C:U
body-use + Glide), `E` (`+use` + C:U grab + Coop RTS), `R`, `F4`, `F6`, `1`,
колесо мыши, `ALT`. Полный список: `ZCity_binds.md`.

## Ограничения

Сборка и валидация сделаны статически: все Lua коннектора прошли `luaparser`,
`addon.json` прошёл JSON-проверку, все ZIP-источники проверены на целостность.
Живой GMod-сервер не запускался. Полная 1:1 совместимость с «чистым»
ZCity + Organs+ не обещается: у `hg.send_organism` фиксированный sendtable, а
синхронизация Organs+ идёт только владельцу.

WIP-пак текстур интерфейса — опциональный: если он ломает HUD, просто удалите
папку `human_hands_for_z_city_casualties_medical_system_heavy_wip`.

## №9: шрапнель только в 4 отмеченных лимбах

По `Screenshot_1-9.png` разрешены только `hand_R`, `hand_L`, `foot_R`,
`foot_L` (обе кисти и обе стопы, обведённые красным). Все источники осколков
сходятся в `WSZC.AddShrapnel` (`sv_zcity_woundsystem_compat_organism.lua`):
`WSZC.ShrapnelSpawnLimb()` переводит попадание в любую другую конечность на
ближайшую отмеченную той же стороны, `SHRAPNEL_MIN_PIECES=3` /
`SHRAPNEL_MAX_PIECES=5` дают 3–5 осколков за попадание. Сохранность при
ragdoll→standing, `RestoreBones`, `ReconcileSpawnShrapnel`, мини-игры и рука
не тронуты. Геометрия куклы по `Screenshot_2-10.png` пересчитана
попиксельно: спрайты степеней двойки (C:U мерит `mat:Width()`, а GMod
округляет PNG до POT), калибровка `S=0.4155`, центр `(682.5,558.2)` по
`Screenshot_1-10.png`. Равномерное ×1.15 и «~2%» отменены live.
Размеры/положение 17 лимбов и hitbox'ы заданы по 1435; шея и таз добавлены в native C:U состояние.

## №10 (по `Screenshot_3-7.png` / `Screenshot_4-6.png`): доводка куклы, курсор и затемнение

1. **Кукла «немного» по прошлому скриншоту.** `Screenshot_3-7.png` подтвердил
   попиксельную калибровку №9: торс, живот, голова и ноги сошлись с
   `Screenshot_2-10.png` в ±1..4 px, габарит `218..864` против `218..865`.
   Оставались только **зазоры между лимбами** — на live они были `6..11 px`,
   у нативной куклы `2..4 px`. `JOINT_ERODE` уменьшен `5 → 3` (MinFilter съедает
   по 1 px вместо 2), предплечья расширены `102 → 110 px`. Итоговая симуляция
   даёт зазоры `2..5 px` и размах рук `610 px` против `612 px`. Цвет, обводка,
   POT-спрайты, `hoverW/hoverH`, симметрия `cx_R + cx_L = 1500` не менялись.

2. **Затемнение заднего фона во ВСЕХ мини-играх, «как раньше».** Причина, по
   которой фон на `Screenshot_4-6.png` оставался ярким: `WSZC.InstallMinigameTextFilter()`
   глушил `WoundSystem.MinigameClip.DrawBackdrop`, а его `draw.RoundedBox`
   дополнительно съедался `HiddenRegionRaw()` как «панель WoundView». Теперь
   `DrawBackdrop` **сохранён** и обёрнут только для двух вещей: ставит
   `_LastMinigameDraw` и на время своего вызова белит `HiddenRegionRaw()`
   (`_MinigameBackdropDrawing`). Все 7 мини-игр C:U (бинт, шприц, осколок,
   вывих, AED, selfharm) вызывают `DrawBackdrop`, поэтому тёмная подложка с
   alpha 200 и мягким краем вернулась везде. `text=all`, `DrawHeader` (иконка
   на месте), `DrawExitGuide`, WoundView-подложка (`..._hide_woundview_backdrop 1`)
   и unconscious blackout не тронуты: мир в WoundView остаётся светлым.

3. **Курсор в мини-игре бинта/шприца.** `gui.MousePos()` замирал, потому что
   C:U `WoundSystem_ScreenClickerWatchdog` вызывает `ForceReleaseScreenClicker`,
   когда его собственный probing `WoundSystemIsAnyWoundMinigameActive()` говорит
   «игры нет» (наши namespaced-копии и игры, открытые из ZCity SWEP, туда не
   попадают), а закрытие радиального меню ZCity снимает кликер ещё раз.
   Исправлено тремя согласованными мерами:
   * `PatchCUMinigameActive()` больше не «одноразовый» — он сравнивает текущую
     глобаль с нашим wrapper'ом и пере-оборачивает её при hot reload / поздней
     загрузке C:U; wrapper учитывает и `MinigameDrawnRecently()`;
   * `WSZC_MinigameCursorWatch` держит `_HoldMinigameCursor = true` для любой
     игры, которая **рисует** `DrawBackdrop` (даже если `IsActive()` её не знает),
     и ре-ассертит кликер каждые `0.05 s`;
   * `gui.EnableScreenClicker(false)` отклоняется, пока `_HoldMinigameCursor`
     активен — кроме единственного легитимного снятия из
     `DisableMinigameClicker()` (`_AllowClickerRelease`). Мышь по-прежнему НЕ
     обнуляется (`SetMouseX/Y` не трогаются), камера заморожена через
     `SetViewAngles`, а блок снимается сам через `0.35 s` после последнего кадра
     мини-игры, поэтому курсор не может «залипнуть» после смерти или закрытия.

Проверено: `S30/S45`, `R24/R32` (backdrop переживает фильтр, watchdog не крадёт
курсор, наш Close всё ещё его отпускает), `ALL_LUA_OK`, `CJK_CLEAN`. Живой GMod
не запускался — принятие по свежим live-скринам.

## №11 (по `Screenshot_6-2.png` / `Screenshot_7.png`): пропорции куклы и одна точка перелома

1. **Пропорции, а не позиции.** Построчное и поколоночное сравнение live с
   `Screenshot_2-10.png` показало, что кукла НЕ сдвинута: голова `98` против
   `100 px`, торс `129/133` против `128/139 px`, бёдра `114` против `112 px`,
   голени `99` против `101 px` — всё в ±1..3 px. Расходилась **толщина рук**:
   все шесть спрайтов давали `44 px` (`y 333..377`) вместо нативных `33..36 px`
   (`y 337..373`), из-за чего конечности выглядели прямоугольными брусками.
   Высота `arm_* / forearm_* / hand_*` в `REFERENCE_BOXES` уменьшена `50 → 40`
   при том же центре: верх и низ сходятся к середине на 4 px каждый. POT-высота
   этих спрайтов стала `128` вместо `256`, но непрозрачный inner box остаётся
   отцентрирован, поэтому `mat:Height() * scale` C:U ставит видимый силуэт на
   прежнее место. Симуляция рендера: `x=470` → `337-373 (37 px)`, `x=500` →
   `336-372 (37 px)`, `x=860/920` → `336-372 (37 px)` против эталона
   `338-373 / 337-372 / 339-371`. Цвет, обводка по форме, POT-ширины,
   `cx/cy`, симметрия `cx_R + cx_L = 1500`, hitbox'ы и шрапнель не менялись.

2. **Перелом в одной точке, вывих на один лимб выше.** ZCity хранит ОДИН флаг
   на всю конечность (`org.larm`, `org.lleg` и `*.dislocation`), а C:U рисует
   ТРИ лимба (`arm/forearm/hand`, `thigh/crus/foot`). Раньше один флаг
   помечал `broken` и `dislocated` сразу на всех трёх — на `Screenshot_7.png`
   это колонка иконок перелома и жёлтых капель вдоль всей ноги. Введён
   `BONE_ANCHOR` + `WSZC.BoneAnchor(limbId, kind)`:
   * **перелом** — только средний лимб: `forearm_L/R`, `crus_L/R`;
   * **вывих** — только лимб выше: `arm_L/R`, `thigh_L/R`;
   * `head` (череп) и `thorax` (рёбра) остаются своими одиночными точками.
   `DISLOC_FLAGS` сужен до одного лимба на флаг, поэтому `FIX DISLOCATION` и
   `WSZC.SyncDislocation()` проверяют вправление именно по якорю, а не по
   устаревшему `false` на соседнем лимбе. Оба пути записи — `RestoreBones()`
   (ragdoll→standing) и 4 Гц `PushShadow` — используют один и тот же якорь.
   Источник истины по-прежнему ванильный `sv_bone.lua` ZCity;organism
   authoritative, Hemogen не задействован, мини-игры и конвары не тронуты.

Проверено: `S33/S46`, `S15 ALL_LUA_OK`, `S16 CJK_CLEAN`, полный suite. Живой
GMod не запускался — принятие по свежему live-скрину.

## №12 (по `Screenshot_8.png` / `Screenshot_9.png`): стыки, кнопка, курсор, рука и лекарства

1. **Стыки и стопы (красные круги на `Screenshot_8`).** Исходные слои архива
   нарезаны под РОДНУЮ куклу C:U: у `arm_*` глубокий диагональный вырез
   подмышки, у `hand_*` неровный торец, у `foot_*` клин-«сапог». После
   POT-калибровки они давали белые щели на каждом суставе. В
   `tools/build_unitmenu_materials.py` добавлены `CloseMask()` (morphological
   closing), `FlattenLimbBand()` (ровная полоса постоянной высоты для
   `arm_*`/`forearm_*`) и `SquareToe()` (прямая подошва для `foot_*`).
   Кисти `hand_*` НЕ выпрямляются — пальцы сохранены. Геометрия
   (`cx/cy/w/h/hoverW/hoverH`), цвет, обводка, симметрия и габарит
   `377..988 × 217..864` не изменились; зазоры стали `3..5 px` против
   эталонных `3..4 px` на `Screenshot_2-10.png`.

2. **Кнопка `FIX DISLOCATION` слишком высоко.** C:U считает
   `targetCenterY = limbScreenPoint.y + OffsetY * dollScale` с авторским
   `OffsetY = -60` из `WoundSystemLimbUIConfig.ShrapnelPoint`. Наша кукла
   упакована в `k = 0.24`, поэтому `dollScale ≈ 1.73` превращает -60 в
   ~-104 ЭКРАННЫХ px — кнопка улетала на весь лимб вверх, на живот.
   `WSZC.PatchActionButtonOffset()` пере-author'ивает `OffsetY = -14`
   (≈ -24 px) для самой точки и всех `Actions` (SHRAPNEL / DISLOCATION /
   TOURNIQUET / SPLINTED) в ГЛОБАЛЬНОМ конфиге, не правя C:U, и один раз
   сбрасывает `WoundSystemActionButtonPos`, чтобы поправка применилась сразу,
   а не за секунду Lerp'а.

3. **Возвращена человеческая рука в режиме C:U.** Прежний режим «только
   стрелка» отменён. `tools/build_minigame_hand.py` поворачивает реальные кадры
   `homigrad/handanim/hand.png` / `3_3.png` в вертикальную CU-позу и создаёт
   `wszc/minigame/hand_idle.png` / `hand_click.png` (512×1260). По умолчанию:
   `zc_woundsystem_compat_handanim 1`, `..._hide_minigame_hand 0`,
   `..._hide_minigame_cursor 1`, `..._hand_pin_cursor 1`. Реальный курсор,
   игровые `handScreenX/Y` и видимый pivot совпадают каждый Think; C:U offset
   `100/400` и spring/collision отставание в этом режиме отключены. Значение `0`
   возвращает HandPhysics, инерцию, наклон и developer offsets;
   системная стрелка скрыта только во время активной мини-игры и возвращается
   на выходе. Для прежнего arrow-only режима: `..._hide_minigame_hand 1`.
   Актуальная миграция `..._hand_mode_revision 6` заменяет слишком большой
   scale `1.0` общим `0.55` во всех мини-играх, оставляя pivot/центр/rotation
   и hitbox'ы C:U. Обычная стрелка подавляется при каждой отрисовке руки и
   при каждом cursor watchdog; прежний безусловный `RestoreMinigameCursor()`
   из watchdog удалён. После миграции ручные настройки не перезаписываются.

4. **Курсор не пропадал после мини-игры.** `DisableMinigameClicker()` раньше
   делал `return` при `WoundSystemHealthHUDOpen == true`, поэтому
   `_HoldMinigameCursor`, `ScreenClickerOwned` и guard `EnableScreenClicker`
   залипали навсегда. Добавлен `WSZC.ForceReleaseMinigameCursor()` (вызывается
   из `WSZC_MinigameClose` и из watchdog при переходе `running -> false`):
   сбрасывает все флаги, возвращает `arrow`, снимает владение C:U и один раз
   отпускает кликер. `WoundSystemIsAnyWoundMinigameActive()` больше НЕ включает
   `MinigameDrawnRecently()` — иначе C:U `DelayedRespawnCursorRelease` и
   `ScreenClickerWatchdog` ещё 0.35 с считали игру активной. Защёлка
   `_MinigameForceOffUntil` живёт 0.4 с (timestamp, не boolean), поэтому
   следующая нативная мини-игра C:U не теряет курсор и заморозку камеры.

5. **Фентанил и подобные не применялись после мини-игр.** Оба `SetupMove`
   хука обнуляли `cmd:SetButtons(0)`, т.е. убивали `IN_ATTACK`, пока
   `MinigameActive()` или нативная C:U `Sessions.Dislocation[ply]` залипали.
   Теперь полный button-lock остаётся ТОЛЬКО у наших bandage/syringe сессий:
   клиент проверяет `WSZC.MinigameHUDOpen == true`, сервер — наличие
   `session`. Для нативных сессий замораживаются лишь движение и углы, а ЛКМ
   проходит, поэтому ZCity медицинские SWEP'ы снова работают. Дополнительно
   серверный watch снимает залипшую C:U Dislocation-сессию старше 20 с.

Проверено: `S47/S48`, `R33`, `S15 ALL_LUA_OK`, `S16 CJK_CLEAN`, полный suite.
Живой GMod не запускался — принятие по свежему live-скрину.

## №13 (по `Screenshot_1-11.png`): пропорция предплечья, видимый курсор, опиоиды

1. **Только пропорция, без перерисовки.** В №12 я ошибся: чтобы закрыть щели,
   применил `CloseMask()` / `FlattenLimbBand()` к рукам и тем изменил сам вид
   (ровные прямоугольники с полосатой альфой). Владелец: «просто предплечие
   пропорционально сделай нормальный к остальной руке а не меняй то как оно
   выглядит». Все 15 силуэтов архива снова отдаются **VERBATIM** для рук и
   кистей; `SEAM_LIMBS`, `CloseMask()`, `FlattenLimbBand()` удалены,
   `SquareToe()` оставлен только для стоп (по кругу на `Screenshot_8`).
   Пропорция исправлена ИСКЛЮЧИТЕЛЬНО числами `REFERENCE_BOXES`: высота
   `arm_*` `40 → 46`, `forearm_*` `40 → 33`. Симуляция рендера C:U:
   плечо `x=560/590` → `29/31 px`, предплечье `x=470/500` → `30 px`,
   кисть `x=410` → `36 px` (пальцы). Раньше было `21-25` против `35`.
   `cx/cy`, длины, POT-ширины, габарит `377..988 × 217..864`, симметрия
   `cx_R+cx_L=1500`, чёрный цвет и обводка по форме не изменились.

2. **Курсор в мини-играх.** Прежняя ошибка была не в самом `blank`, а в том,
   что стрелку скрывали при уже отключённой руке: игрок оставался вообще без
   указателя. Теперь `SyncMinigameCursor()` разрешает `blank` только при
   активной мини-игре и `ShowMinigameHand() == true`; при
   `hide_minigame_hand 1`, после закрытия и для мёртвого игрока всегда
   восстанавливается `arrow`. `WSZC_MinigameCursor` (Think) проверяет
   `vgui.CursorVisible()` и перезапускает clicker после C:U watchdog /
   радиального меню ZCity, не выключая mouse input. `UnitmenuHandMat()`
   дополнительно вызывает `SyncMinigameCursor()` на КАЖДОЙ отрисовке руки,
   поэтому стрелка не возвращается между периодическими Think-проверками.
   Старые archived no-hand настройки мигрирует `MigrateHumanHandDefaults()` (revision 6),
   поэтому обновление не оставляет прежнюю комбинацию «нет руки + blank».
   Ручной выбор arrow-only сохраняется и больше не перезаписывается.

3. **Морфин / фентанил / обезболивающие.** Настоящая причина найдена в
   `z_city/lua/homigrad/woundbridge/sv_woundbridge.lua` и
   `z_city/lua/weapons/weapon_{fentanyl,morphine}.lua`:
   `SWEP:Heal()` начинается с
   `local wbr = hg.WoundBridge.SwepHeal(...); if wbr ~= nil then return wbr end`.
   `WB.SwepHeal` для этих SWEP'ов открывает syringe-мини-игру и возвращает
   `false` — значит нативный ZCity код `org.analgesiaAdd += injected` **не
   выполняется никогда**, а эффект применяется только по завершении
   мини-игры. Раз курсор не работал, мини-игра не завершалась и лекарство
   не действовало (отсюда «после мини игр нету применения»). Дополнительно
   нашёлся второй пропуск: C:U пишет дозу в `body.opiateAmount`
   (`sh_fentanyl.lua`: `opiateAmount = 420`), а `WSZC.ApplyMedicalDelta()`
   переносил в organism всё, КРОМЕ опиоида. Теперь `Snapshot()` хранит
   `opiateAmount`, а `ApplyMedicalDelta()` пишет
   `org.analgesiaAdd += ΔopiateAmount * 0.006` (кладется в диапазон `0..4`).
   ZCity `sv_pain.lua:116` читает `org.analgesiaAdd > 0` и поднимает
   `org.analgesia` до 4, так что обезболивание/седация реально работают.
   Плюс от №12 сохраняются: снятие `SetButtons(0)` для нативных сессий,
   `_MinigameForceOffUntil` и `ForceReleaseMinigameCursor()`.

Проверено: `S48/S49`, `R10/R11/R12`, `S15 ALL_LUA_OK`, `S16 CJK_CLEAN`,
полный suite. Живой GMod не запускался — принятие по свежему live-скрину.

## №14: «интерфейс не точный в плане расставления и размеров» — попиксельная подгонка, стиль не трогаем

Владелец: «сделай также но с нашей стилистикой типо обводки и черного цвета».
То есть геометрия/размеры должны совпадать с нативной куклой
`Screenshot_2-10.png`, а **оформление остаётся нашим**: чистый чёрный
`DOLL_RGB=(0,0,0)` и тонкая обводка по контуру КАЖДОГО лимба (не рамки, не
прямоугольные полосы). Рукописных «на глаз» правок больше нет.

**Что сделано.** Добавлен `tools/fit_unitmenu_geometry.py`: он берёт 15
силуэтов архива **VERBATIM**, рендерит их в экранные координаты ровно по той
же линейной формуле, что и C:U (`S=0.4155`, центр `(682.5, 558.2)`, размер
спрайта = POT `mat:Width()/Height()`), и сравнивает чёрную маску с куклой на
`Screenshot_2-10.png`. Фон комнаты там RGB `30..80`, кукла `0..8`, поэтому
`max(RGB) < 20` выделяет куклу без шума; `MedianFilter(3)` убирает антиалиасинг.
Ограниченный coordinate descent по `(tx, ty, w, h)` — пары зеркально
симметричны относительно `x=682.5`, размеры в пределах ±35%, форма НЕ
рисуется заново — поднял **IoU с 0.8497 до 0.9090**.

**Итоговые числа `REFERENCE_BOXES`** (только позиции и пропорции):

| лимб | было | стало |
|---|---|---|
| head | `(682.5,267,70,102)` | `(682.5,268,67,102)` |
| thorax | `(682.5,385.5,122,131)` | `(681.5,385.5,124,129)` |
| abdomen | `(682.5,521.5,132,141)` | `(681.5,521.5,129,140)` |
| arm_R/L | `(578.9/786.1,355,82,46)` | `(576.9/788.1,361,86,54)` |
| forearm_R/L | `(480/885,355,110,33)` | `(479/886,356,110,38)` |
| hand_R/L | `(400/965,355,47,40)` | `(399/966,355,47,42)` |
| thigh_R/L | `(652.5/712.5,650,60,116)` | `(652.5/712.5,650,58,114)` |
| crus_R/L | `(649.5/715.5,759,46,102)` | `(650.5/714.5,760,48,101)` |
| foot_R/L | `(650/715,837.5,45,55)` | `(648/717,842,38,50)` |

Плечо теперь закрывает нативную полосу `y≈336..373`, предплечье `y≈337..375`,
кисти и стопы встали на свои места; между голенью и стопой сохранён нативный
зазор ~5 px. Оставшиеся красные пиксели оверлея — это авторские подмышечные
вырезы (их заполнять запрещено прошлым «а не меняй то как оно выглядит») и
шрапнель/фон эталона.

**Что НЕ менялось:** 15 силуэтов архива, `SquareToe()` только для стоп,
`JOINT_ERODE=3`, `EDGE_PAD_MIN=6`, `EDGE_WIDTH=9`, чёрный цвет, обводка по
форме, T-pose, симметрия `cx_R+cx_L=1500`, `0.0%` белого на границах спрайтов,
затемнение мини-игр, человеческая C:U-рука вместо системного курсора, `analgesiaAdd` для опиоидов,
перелом/вывих на один лимб, шрапнель на 4 лимба.

Проверить локально:
`PYTHONPATH=/tmp/pil_pkg python3 tools/fit_unitmenu_geometry.py --reference /path/Screenshot_2-10.png --overlay /tmp/overlay.png`
(жёлтый = совпадение, красный = только эталон, зелёный = только наш рендер).

Suite `82/82` до пересборки архивов, затем полный прогон. Живой GMod не
запускался — принятие по свежему live-скрину.
