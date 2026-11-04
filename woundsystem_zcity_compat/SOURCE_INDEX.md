# Исходный код коннектора

Аддон полностью состоит из открытого Lua-кода; бинарных/скомпилированных
модулей нет. Все файлы лежат в `lua/autorun/` и загружаются штатным порядком
GMod. Исходные ZIP-аддоны не изменяются: всё патчится в рантайме.

| Файл | Сторона | Что делает |
|---|---|---|
| `lua/autorun/sh_zcity_woundsystem_compat.lua` | shared | `WSZC.OrganismAuthority()`, конвар `zc_woundsystem_compat_authority`, `WithVanillaContext`, `PatchIsEnabled`, `PatchIsBridged` (weak-key `BridgedWrappers`), повторные попытки инициализации |
| `lua/autorun/server/sv_zcity_woundsystem_compat.lua` | server | Основной мост: weak-key `WSZC.RawDamage`, `DamageWrapper`, снимки/дельты медицины в `ApplyItemToBodyImpl`, публикация `WSZC_Ready` / `WSZC_OrganismAuthority`, `Setup()`/`Attempt()`, mode-aware `InstallOrganismMode` |
| `lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua` | server | Authority-слой: единый `state.shrapnel`, `InjectDamageShrapnel` (пули/взрывы/стекло), `Constants()` из реального `WoundSystem.Health.Constants`, `WrapHook` с `wrappedByKey`, glass brush/ragdoll, shadow-синхронизация, `WB.SwepHeal`, подавление второй физиологии, 5-секундный reapply, очистка при спавне |
| `lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua` | server | instant / watchdog / continuous мини-игры, виртуальный слот `6`, `WSZC_*` net-сообщения |
| `lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua` | client | Пункт «Проверить травмы» в круговом меню ZCity → `WoundSystem.OpenHealthHUD()`, gate `WSZC_Ready`, `OPEN_DELAY = 0.12`, `wszc_open_wounds` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua` | client | Клиентская часть мини-игр, приём `WSZC_*` |
| `lua/autorun/client/wszc_cl_bandage.lua` | client | Порт родной C:U мини-игры бинтования (ЛКМ/ПКМ/ESC) |
| `lua/autorun/client/wszc_cl_syringe.lua` | client | Порт родной C:U мини-игры шприца (ЛКМ/ПКМ/ESC) |
| `addon.json` | мета | `title`, `type: ServerContent`, ignore `*.md`/`*.txt` |
| `README.md` | доку | Установка, подписки Мастерской, таблицы предметов/шрапнели, конвары, диагностика, ограничения |

## Ключевые решения

* `ply.organism` (ZCity) — единственный источник истины о здоровье.
* C:U остаётся UI, мини-играми, «теневыми» метриками и протоколом шрапнели;
  `woundsys_enabled` не выключается.
* Gunshot/blast хуки C:U подавлены, их правила перенесены в единый
  `WSZC.InjectDamageShrapnel`; стекло — единственный новый источник.
* `state.shrapnel` без поля `source`, без второй мини-игры; лимит 5 из
  `WoundSystem.Health.Constants.ShrapnelPieceCount`.
* Сырой урон ловится `pre`-хуком до `sv_input.lua:1085 ScaleDamage(0.15)`;
  `WoundSystem_Damage` не вызывается повторно (там `dmginfo:SetDamage(0)`).
* `zc_woundsystem_compat_authority 0` возвращает прежний мост,
  `zc_woundsystem_bridge 0` отключает коннектор целиком.

Валидация: все 8 Lua-файлов проходят `luaparser`, `addon.json` — JSON-парсер,
три Lua-теста (organism / inspect / minigames) — `TEST_OK`. Живой GMod-сервер
не запускался.
