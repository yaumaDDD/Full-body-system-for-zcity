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
| Кукла WoundView собрана из 15 слоёв `unitmenu/limbs` архива + иконки статусов | `zc_woundsystem_compat_unitmenu_doll 1`, размер `zc_woundsystem_compat_unitmenu_scale 0.28` (диапазон `0.1..0.8`) |
| Все 647 UI-материалов внутри сборки (без ERROR и ручного копирования) | `woundsystem_zcity_compat/materials/` + зеркало в `casualties_unknown_health_system_beta/materials/`, генератор `tools/pack_ui_materials.py` |
| Рука в мини-играх — кадры `homigrad/handanim` из архива (ладонь/кулак) | `zc_woundsystem_compat_handanim 1`, размер `zc_woundsystem_compat_handanim_scale 0.55` (диапазон `0.2..1.5`) |
| Зелёные полосы/лёгкие/ЭКГ сканера слева скрыты | `zc_woundsystem_compat_hide_unit_panel 1` (глушатся `DrawTexturedRectUV`, `DrawLine`, `DrawPoly`) |
| Экран смерти C:U не рисуется, но ЛКМ респавнит | включается вместе с `zc_woundsystem_compat_disable_cu_fx 1`; хук обёрнут, а не удалён |
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
