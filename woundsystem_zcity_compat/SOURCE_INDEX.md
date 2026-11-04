# Исходный код коннектора

Аддон полностью состоит из открытого Lua-кода; бинарных/скомпилированных
модулей нет. Все файлы лежат в `lua/autorun/` и загружаются штатным порядком
GMod. Исходные ZIP-аддоны не изменяются: всё патчится в рантайме. Исключение —
одна строка `Not completed - nothing was applied` в `sv_woundbridge.lua`,
которая убрана только внутри пересобранного `zcity_full_pack.zip` как дублёр
рантайм-фильтра (см. ниже).

| Файл | Сторона | Что делает |
|---|---|---|
| `lua/autorun/sh_zcity_woundsystem_compat.lua` | shared | `WSZC.OrganismAuthority()`, конвар `zc_woundsystem_compat_authority`, `WithVanillaContext`, `PatchIsEnabled`, `PatchIsBridged` (weak-key `BridgedWrappers`), повторные попытки инициализации |
| `lua/autorun/server/sv_zcity_woundsystem_compat.lua` | server | Основной мост: weak-key `WSZC.RawDamage`, `DamageWrapper`, снимки/дельты медицины в `ApplyItemToBodyImpl`, публикация `WSZC_Ready` / `WSZC_OrganismAuthority`, `Setup()`/`Attempt()`, mode-aware `InstallOrganismMode` |
| `lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua` | server | Authority-слой: единый `state.shrapnel`, `InjectDamageShrapnel` (пули/взрывы/стекло), `Constants()` из реального `WoundSystem.Health.Constants`, `WrapHook` с `wrappedByKey`, glass brush/ragdoll, per-limb shadow-синхронизация, масштаб адреналина/обезболивающего, `WB.SwepHeal`, подавление второй физиологии, 5-секундный reapply |
| `lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua` | server | instant / watchdog / continuous мини-игры, виртуальный слот `6`, `WSZC_*` net-сообщения, рантайм-фильтр надписи «Not completed - nothing was applied» |
| `lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua` | client | Full-screen мини-игры: переопределение `WoundSystem.MinigameClip.GetRect()`, единый `WSZC.MinigameScale()`, клиентский кламп `org.adrenaline`/`org.painkiller` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua` | client | Пункт «Проверить травмы» в круговом меню ZCity → `WoundSystem.OpenHealthHUD()`, gate `WSZC_Ready`, `OPEN_DELAY = 0.12`, `wszc_open_wounds` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua` | client | Клиентская часть мини-игр, приём `WSZC_*` |
| `lua/autorun/client/wszc_cl_bandage.lua` | client | Порт родной C:U мини-игры бинтования (ЛКМ/ПКМ/ESC), layout на весь экран |
| `lua/autorun/client/wszc_cl_syringe.lua` | client | Порт родной C:U мини-игры шприца (ЛКМ/ПКМ/ESC), board = весь экран, оффсеты в долях viewport |
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

## Исправления по четырём скриншотам

| Симптом | Причина | Исправление |
|---|---|---|
| Мини-игра — маленький квадрат ~760 px в центре | `Clip.GetRect()` из `cl_clip.lua` задаёт и фон, и stencil/scissor; `DPanel` на весь экран уже был | `cl_zcity_woundsystem_compat_layout.lua` переопределяет `GetRect()` на `0,0,ScrW,ScrH,0`; `board` и оффсеты пересчитаны в долях экрана, симуляционные координаты не тронуты |
| «Not completed - nothing was applied» по центру | локальный `Nothing()` в `sv_woundbridge.lua:1076` шлёт `HUD_PRINTCENTER` при закрытии мини-игры без дозы | точный фильтр этого сообщения через обёртку `Player.PrintMessage`; конвар `zc_woundsystem_compat_hide_empty_notice` (по умолчанию `1`) |
| Радиальные полосы / тряска / «My muscles are burning» | C:U хранит `body.adrenaline` 0..100 и ставит 100 при ранении; дельта переливалась в `org.adrenaline` (норма ≤2), а `cl_camera.lua` умножает adrenaline на 5 в FOV | дельта `*0.02` с клампом 2, `painkiller` `*0.01` с клампом 1, `body.*` зеркалятся из organism; дополнительный клиентский кламп для уже испорченных организмов |
| Дробовик в ногу → кровь на всех 15 лимбах | `PushShadow` писал один глобальный `org.bleed` в КАЖДЫЙ C:U limb | `LimbBleedMap()` читает `org.wounds[n][4]` (имя кости) и `org.arterialwounds[n][7]` (`rlegartery` и т.п.), мапит в limb id; внутреннее кровотечение остаётся в `body.internalBleeding` |
| Дробовик в ногу → нет шрапнели | 1) `homigrad-damage` возвращает `true` и пересылает хит в `FakeRagdoll`, GMod даёт `PostEntityTakeDamage took=false`, старый код это отбрасывал; 2) у `12/70 gauge` `dmgtype` закомментирован в `sh_ammostuff.lua`, пули приходят как `DMG_GENERIC`, а проверялись только `DMG_BULLET/DMG_BUCKSHOT` | инжекция в `CaptureRawDamage` (до `return true`) + fallback в `PostEntityTakeDamage`, weak-key дедуп `ShrapnelHandled`, `IsBallisticHit()` по `dmginfo:GetAmmoType()`/`game.GetAmmoName()` и `inf.NumBullet > 1`, расширенный `BONE_HITGROUPS` (бедро/голень/предплечье) |

Валидация: все 9 Lua-файлов проходят `luaparser`, `addon.json` — JSON-парсер,
headless-тесты `TEST_OK 9/9` (шрапнель,took=false, дедуп, адреналин, per-limb
кровотечение) и `TEST_OK 6/6` (full-screen clip, zoom, кламп). Живой
GMod-сервер не запускался.
