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
| Мини-игры бинта/шприца на весь экран | `zc_woundsystem_compat_fullscreen_minigame 1`, размер — `zc_woundsystem_compat_minigame_zoom 1.0` |
| Нет надписи «Not completed - nothing was applied» | `zc_woundsystem_compat_hide_empty_notice 1` |
| Нет «адреналинового» FOV-взрыва и радиальных полос | `zc_woundsystem_compat_clamp_adrenaline 1` |
| Кровотечение только на раненых лимбах | `zc_woundsystem_compat_limb_bleed 1` |
| Шрапнель от дробовика/взрыва | `zc_woundsystem_compat_shrapnel 1`, `zc_woundsystem_compat_shrapnel_on_blocked 1` |
| Только эффекты ZCity: все эффекты C:U выключены | `zc_woundsystem_compat_disable_cu_fx 1` |
| Кровь C:U убрана, ванильная кровь ZCity/Hemogen возвращена | `zc_woundsystem_compat_disable_cu_blood 1` |
| В мини-игре персонаж не ходит, не крутит камерой и виден курсор | включается вместе с `zc_woundsystem_compat_minigames 1` (без отдельного конвара) |
| Шрапнель только от дробовика и взрыва, не от пистолетов | `zc_woundsystem_compat_shrapnel_only_shotgun_blast 1` |
| Осколок ложится в раненую конечность (`org.dmgstack` / `HitBones`) | включается вместе с `zc_woundsystem_compat_shrapnel 1` |
| `reset organism` не поднимает персонажа, структура ZCity сохранена | `zc_woundsystem_compat_preserve_reset_structure 1` |
| Шрапнель сохраняется при падении/подъёме из ragdoll | включается вместе с `zc_woundsystem_compat_shrapnel 1` |
| Стекло в ragdoll (руки/ноги) даёт осколки | `zc_woundsystem_compat_glass_shrapnel 1` |
| Ошибки в shrapnel-мини-игре → боль и нарастающее кровотечение | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Рука/курсор работают в мини-игре шприца | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Вывихи вправляются вручную (`FIX DISLOCATION` в WoundView), состояние в `ply.organism` | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Переломы видны в WoundView, но считаются/лечатся ZCity (`sv_bone.lua`) | включается вместе с `zc_woundsystem_compat_shadow 1` |
| Инвентарь C:U скрыт, слот `6` для ZCity SWEP'ов остаётся | `zc_woundsystem_compat_hide_cu_inventory 1` |
| Панель `UNI-HEALTH` / unit внутри WoundView скрыта | `zc_woundsystem_compat_hide_unit_panel 1` |
| Рамки слотов и `UNI-HEALTH` скрыты и при нестандартном масштабе UI | `zc_woundsystem_compat_hide_cu_inventory 1`, `zc_woundsystem_compat_hide_unit_panel 1` (фильтр через `hook.Add`; `PreDrawHUD` — запасной контур) |
| Предмет / viewmodel в руках скрыт в мини-игре | включается вместе с `zc_woundsystem_compat_minigames 1` |
| WoundView не наслаивается поверх мини-игры | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Нативная мини-игра вправления меньше исходного квадрата C:U | `zc_woundsystem_compat_native_minigame_zoom 0.75` (диапазон `0.4..1.2`) |
| Кость вправления рядом с суставом и на экране | `zc_woundsystem_compat_dislocation_start 35` (диапазон `10..100`) |
| Рука не трясётся и уменьшена | `zc_woundsystem_compat_hand_cursor_scale 0.45` (диапазон `0.2..1`) |
| Кукла WoundView собрана из 15 слоёв `unitmenu/limbs` архива + иконки статусов | `zc_woundsystem_compat_unitmenu_doll 1`, размер `zc_woundsystem_compat_unitmenu_scale 0.24` (диапазон `0.1..0.8`) |
| Все 647 UI-материалов внутри сборки (без ERROR и ручного копирования) | `woundsystem_zcity_compat/materials/` + зеркало в `casualties_unknown_health_system_beta/materials/`, генератор `tools/pack_ui_materials.py` |
| Рука в мини-играх — кадры `homigrad/handanim` из архива (ладонь/кулак) | `zc_woundsystem_compat_handanim 1`, размер `zc_woundsystem_compat_handanim_scale 0.55` (диапазон `0.2..1.5`) |
| Зелёные полосы/лёгкие/ЭКГ сканера слева скрыты | `zc_woundsystem_compat_hide_unit_panel 1` (глушатся `DrawTexturedRectUV`, `DrawLine`, `DrawPoly`) |
| Экран смерти C:U не рисуется, но ЛКМ респавнит | включается вместе с `zc_woundsystem_compat_disable_cu_fx 1`; хук обёрнут, а не удалён |
| Кукла не обрезается слева/снизу, видны `REMOVE SHRAPNEL` и `FIX DISLOCATION` | `WSZC.InstallMaterialTracker()` + `WSZC.IsDollDrawMaterial()`; размер `zc_woundsystem_compat_unitmenu_scale 0.24` |
| Осколки от ударов кулаками по стеклу | `zc_woundsystem_compat_shrapnel 1`, `zc_woundsystem_compat_glass_shrapnel 1`, резервный хук `WSZC_GlassStrikePre` на `EntityTakeDamage`; диагностика `zc_woundsystem_compat_organism_debug 1` |
| Кровь `project hemogen blood` не изменена | compat не обращается к `advancedblood/*`; ERROR-квадраты — отсутствующие материалы самого аддона |
| WSZC мини-игры на весь экран; нативные C:U — в авторском размере | `zc_woundsystem_compat_fullscreen_minigame 1`, `zc_woundsystem_compat_fullscreen_native 0`, `zc_woundsystem_compat_native_minigame_zoom 1`. Растяжение нативных игр давало огромный обрезанный осколок и уводило нижнюю часть раны за экран |
| Нет белых пустых слотов и чёрной подложки поверх куклы | `HiddenRegionRaw()` для `DrawOutlinedRect`/`DrawRect`/`RoundedBox`/`DrawLine`/`DrawPoly`; whitelist только для текстур и текста |
| После «Reset organism» снова можно быстро бегать | `RESET_KEEP` больше не несёт `canmove/stun/consciousness/brain`; `WSZC.ClearMovementPenalties()` снимает штрафы движения во всех трёх путях ресета |
| Кукла с человеческими пропорциями, как на эталонном фото | `tools/build_unitmenu_materials.py`: явный `HUMAN_LAYOUT` (маленькая голова, узкий короткий торс, тонкие руки T-pose, длинные узкие ноги, компактные целые стопы; вертикальные швы сняты с нативной куклы `Screenshot_2-10.png`), **стандартный чёрный `(0,0,0)`** `_fill` с эрозией 1 px (`JOINT_ERODE = 3`) + тонкая белая обводка **по форме каждого лимба** (`EDGE_PAD_MIN=6`, ноль белых пикселей на границах спрайтов). Анатомия наша, не родная C:U. `zc_woundsystem_compat_unitmenu_tint 1` ставит белый `SetDrawColor` **только** для `*_fill.png`; `*_edge.png` остаётся под `finalOutline` C:U, поэтому реакция на наведение (белый → чёрный) штатная |
| Лишний текст убран, затемнение фона сохранено во всех мини-играх | `zc_woundsystem_compat_hide_minigame_text 1`: `WSZC.InstallMinigameTextFilter()` обнуляет `title/value/guide/panelAlpha` в `Clip.DrawHeader` (иконка остаётся), глушит `Clip.DrawExitGuide` и **сохраняет `Clip.DrawBackdrop`** (затемнение фона), точечно фильтрует chrome-шрифты (`RetroTooltipTitle*`, `RetroTooltipDesc*`, `RetroMinigameGuide*`) **и AED `WoundSystemAEDStatus`** (только пока мини-игра активна). `minigameshrapnel.png` — передний слой раны, **не удаляется**; все игровые спрайты защищены `WSZC.IsMinigameGameplaySprite()`. Уведомления ZCity, статусные надписи C:U (кроме AED), красный death-текст, капли, `Icons.*`, осколки и рука не трогаются; `0` — вернуть как было |
| Рука мини-игры без инерции | `zc_woundsystem_compat_hand_pin_cursor 1` → реальный `gui.MousePos()` и синхронизация `MG.handScreenX/Y`; поворот `0`, курсор скрыт |
| Светлый фон WoundView | `zc_woundsystem_compat_hide_woundview_backdrop 1` гасит полноэкранный `woundbg`/blackout только пока `WoundSystemHealthHUDOpen == true` |
| Рука в мини-игре ровно на курсоре | `zc_woundsystem_compat_hand_pivot_x 0.16`, `zc_woundsystem_compat_hand_pivot_y 0.45`, поворот `0`, лимит `zc_woundsystem_compat_hand_max_screen 0.34` |
| Системный курсор в мини-игре не виден | `zc_woundsystem_compat_hide_minigame_cursor 1` → VGUI-курсор `"blank"`, мышь работает; `0` — вернуть стрелку |
| После смерти не «залипают» мини-игры/курсор/лок движения | включается вместе с `zc_woundsystem_compat_minigames 1` |
| Если респавн не сработал | подождите 1 с после смерти и нажмите ЛКМ; откат визуала C:U — `zc_woundsystem_compat_disable_cu_fx 0` |

Ассеты для куклы и руки берутся из архива `для переделывания интерфейса.zip`
(`origin/main`). Нарезанные PNG лежат в `woundsystem_zcity_compat/materials/wszc/unitmenu/`,
кадры руки — в `.../materials/homigrad/handanim/` (оба набора внутри коннектора,
WIP-аддон больше не обязателен), а весь `casunknown-images/*` — рядом с ними и
дублируется в папку C:U. Скрипты пересборки —
`tools/build_unitmenu_materials.py` и `tools/pack_ui_materials.py`, список с
хэшами — `woundsystem_zcity_compat/MATERIALS.sha256`. Ни один Lua-файл внутри
исходных ZIP-аддонов не изменён.

Панель травм, HUD и протокол шрапнели C:U при этом остаются — отключаются только
визуальные эффекты, декоративная кровь, инвентарь C:U и левый сканер
`UNI-HEALTH`, а не сам WoundView.

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

**Про C:U — важное исключение.** В исходном ZIP репозитория лежат только Lua,
3 шрифта и 3 шейдера — `materials/` и `sound/` там нет. Сборка **уже добавила**
все UI-материалы (647 файлов) и в `woundsystem_zcity_compat/materials/`, и в
`casualties_unknown_health_system_beta/materials/`: WoundView, лимбы, иконки,
экраны и мини-игры больше не показывают ERROR, вручную ничего перекидывать не
надо, `woundsys_resource_downloads 1` для них не требуется. Остаются только
звуки C:U (в архивах их нет) и шейдеры `3440271589`; за ними — один из двух
вариантов:

* **Вариант А (рекомендуется, точная версия):** оставить папку из пакета и
  отдельно докачать контент C:U на сервер, включив
  `woundsys_resource_downloads 1` (файлы должны физически лежать в
  `garrysmod/`). Подписку на C:U в Мастерской при этом **не добавлять**.
* **Вариант Б (проще):** подписаться на C:U `3728573930` и обязательный
  `Simple Custom Shaders` `3440271589`, а папку
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
zc_woundsystem_compat_inspect_button 1  кнопка «Проверить травмы» в радиал-меню
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
Изменены только размеры/положение 15 лимбов и hitbox'ы.

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
