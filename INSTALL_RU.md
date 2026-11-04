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

**Про C:U — важное исключение.** В пакет уже положена папка
`casualties_unknown_health_system_beta` из репозитория (Lua, 3 шрифта,
3 шейдера). Это **не полный** аддон: в ZIP нет `materials/` и `sound/`, которые
перечислены в `sv_resources.lua`. Поэтому нужно одно из двух:

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
