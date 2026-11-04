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
| `lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua` | server | Authority-слой: единый `state.shrapnel`, `IsShotgunHit()` (только дробовик/взрыв), `FreshHitgroup`/`LimbFromHitBones` (limb из `org.dmgstack`/`HitBones`), `InjectDamageShrapnel` в `PostEntityTakeDamage`, `WSZC.RestoreShrapnel`/`SyncShrapnel` (двусторонняя синхронизация, сохранение в ragdoll), `WSZC_GlassRagdoll` (стекло в fake ragdoll), `ApplyShrapnelComplication` + irritation (боль/нарастающее кровотечение от мини-игры), `InstallResetStructureGuard()`, `Constants()`, `WrapHook`, per-limb shadow, `DisableCUBloodReplacement()`, `WB.SwepHeal`, 5-секундный reapply |
| `lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua` | server | instant / watchdog / continuous мини-игры, виртуальный слот `6`, `WSZC_*` net-сообщения, рантайм-фильтр надписи «Not completed - nothing was applied», `session.frozenAngles` и серверный `SetupMove`-лок движения + камеры |
| `lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua` | client | Full-screen мини-игры: переопределение `WoundSystem.MinigameClip.GetRect()`, единый `WSZC.MinigameScale()`, клиентский кламп `org.adrenaline`/`org.painkiller` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_fx.lua` | client | Фильтр эффектов C:U: снимает `RenderScreenspaceEffects`/`CalcView`/`HUDPaint*`/`PostDrawHUD`/`CreateMove`/fog-хуки и blood-хуки, нейтрализует `TextCorruption`, выставляет визуальные конвары C:U в `0`, умеет восстанавливать оригиналы |
| `lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua` | client | Пункт «Проверить травмы» в круговом меню ZCity → `WoundSystem.OpenHealthHUD()`, gate `WSZC_Ready`, `OPEN_DELAY = 0.12`, `wszc_open_wounds` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua` | client | Клиентская часть мини-игр, приём `WSZC_*`, владение курсором без мигания, заморозка `ViewAngles` без подавления GUI-мыши (`InputMouseApply` НЕ возвращает `true`), пропуск `+attack`/`+attack2` в UI, блокировка движения `SetupMove` |
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

## Только эффекты ZCity, без крови C:U, с рабочим курсором

| Требование | Реализация |
|---|---|
| Убрать ВСЕ эффекты C:U | `cl_zcity_woundsystem_compat_fx.lua` содержит точный список `hook.Remove`: `WoundSystem_PostProcess`, `StaminaEffects`, `BlindEffects`, `ChromaticAberration`, `SpinNausea*`, `Lobotomy*`, `BrainReverse*`, `DrawManualStatic`, `FullStatic`, `BlindVignette`, `VignetteVisuals`, `MoodlesPaint`, `SelfTalkHUDPaint`, `DeathScreenDisplay`, `DrawMoodIcon`, `Unconscious*`, `EYEVIEW_CalcView`, `BlackSkybox`, world/sky fog, `BallisticAimKick`. **Не трогаются** `WoundDollAndPanel`, `WoundSystem_UIRegistry`, `ToggleHUDInput`, `WoundSystem_ScreenClickerWatchdog` — панель и курсор остаются. `TextCorruption.ShouldCorrupt/Corrupt` нейтрализованы; конвары `woundsys_pain_shader_enabled`, `moodles`, `nausea`, `visual_quality`, `self_talk` и др., а также аудио C:U (`audio_master`, `music_enabled`, `tinnitus_volume`, pain/death/growl sounds, `chat_distortion`, `gunshot_hearing`, `hev`) выставляются в `0`; снимаются `HealthSystem_InitAudio`, `HealthSystem_AudioCrossfade`, `WoundSystem_AsystoleSound` и self-talk ticker. Оригиналы хуков сохраняются в `WSZC.CUFxSaved` и возвращаются при `zc_woundsystem_compat_disable_cu_fx 0`; фильтр повторяется раз в секунду, т.к. C:U пересоздаёт `EYEVIEW_CalcView` из своего Think |
| Убрать кровь C:U | Снимаются `WoundSystem_BloodEffects_Think/Draw`, `FurBloodModelOverlay`, `FurBloodRagdollOverlay`; конвары `woundsys_blood_effects/stains/trails/bodyflow/quality`, `woundsys_fur_blood_models` → `0`. На сервере `WSZC.DisableCUBloodReplacement()` патчит `Health.Config.ApplyVanillaBloodMode`, который по умолчанию ставит `DONT_BLEED` и **глушит ванильную кровь ZCity/Hemogen** — теперь игрокам возвращается `BLOOD_COLOR_RED`. Откат: `zc_woundsystem_compat_disable_cu_blood 0` |
| Курсор в мини-игре | `WoundSystem_ScreenClickerWatchdog` снимает курсор, когда `WoundSystemIsAnyWoundMinigameActive() == false`, а этот глобал знает только 6 нативных мини-игр C:U. Коннектор оборачивает его (`original() or WSZC.MinigameActive()`), повторно включает кликер в `Think`, если его украли, и даёт 1 секунду grace между `WSZC_MinigameOpen` и `WSZC_BandageOpen`/`WSZC_SyringeOpen` (раньше watchdog успевал сбросить `MinigameHUDOpen` до старта UI) |
| Персонаж не ходит | Клиентский и серверный `SetupMove` (`WSZC_MinigameLockMovement` / `WSZC_MinigameServerLock`) обнуляют `forward/side/up`, `buttons`, `mousex/mousey` и горизонтальную скорость, сохраняя падение по Z. `PlayerBindPress` блокирует бинды ZCity (`+forward`, `+menu`, `slot*`, …), кроме `toggleconsole`/`screenshot`/`jpeg` |

## Источники шрапнели, конечность, reset и камера (последняя правка)

| Требование | Реализация |
|---|---|
| Не от пистолетов | `IsShotgunHit()` вместо `IsBallisticHit()`: убраны `DMG_BULLET` и эвристика «NxM mm» (из-за неё `9x19 mm` считался дробью). Остались `DMG_BUCKSHOT`, ammo `12/70*` / `20/70*` / `23x75*`, `NumBullet > 1` или класс shotgun-SWEP у инфликтора/активного оружия. Взрыв — отдельная ветка `DMG_BLAST`. Конвар отката `zc_woundsystem_compat_shrapnel_only_shotgun_blast` |
| Не «непонятно где» | `DamageLimb()` больше не гадает по ближайшей кости и не имеет fallback `thorax`. Приоритет: `org.dmgstack[hitgroup]` (ZCity пишет урон и `CurTime()`), `ply:LastHitGroup()`, `ply.HitBones`, затем `GetDamagePosition()` с порогом 55 юнитов. Если limb неизвестен — фрагмент не создаётся. Инъекция перенесена из `CaptureRawDamage` в `PostEntityTakeDamage`, т.к. `dmgstack` заполняется внутри ZCity-хука |
| `reset organism` не встаёт | `InstallResetStructureGuard()` оборачивает `hg.organism.Clear` и `WB.ResetOrganism`: `WB.RestoreRagdoll` временно заменяется no-op (иначе `timer.Simple(0)` → `hg.FakeUp` сработает после обёртки), а `otrub/needotrub/fake/needfake/canmove/alive/stun/consciousness/...` снимок возвращается после очистки (травмы и `health` всё равно сбрасываются); повторно шлются `hg.send_organism`/`hg.send_bareinfo` и обновляется shadow. Обычный спавн без ragdoll/unconscious не затрагивается. Конвар `zc_woundsystem_compat_preserve_reset_structure` |
| Не крутить камеру | Клиент сохраняет `LocalPlayer():EyeAngles()` при `WSZC_MinigameOpen`; `InputMouseApply` (return true), `CreateMove` и `SetupMove` forcibly `cmd:SetViewAngles(frozen)`. Сервер хранит `session.frozenAngles` и делает то же в `WSZC_MinigameServerLock`. `WSZC_MinigameClose` и watchdog снимают заморозку |

## Шрапнель в ragdoll, стекло, осложнения и ввод в мини-игре

| Требование | Реализация |
|---|---|
| Осколки не пропадают при падении в ragdoll | C:U `InitPlayer()` создаёт НОВУЮ таблицу `PlayerLimbs[ply]` на `Fake`/`FakeUp`/`WoundSystem_SpawnSync`; старый `PullShrapnel` тянул пустую таблицу в `ply.organism`. `WSZC.SyncShrapnel()` сравнивает ссылку на таблицу (`ply._WSZCLimbsRef`): новая → `WSZC.RestoreShrapnel()` пишет осколки ИЗ организма обратно в C:U (в т.ч. через `GetLimbState`, если limb ещё не создан); та же → честно тянет результат извлечения. Дополнительно `hook.Add("Fake"/"FakeUp"/"HG_OnWakeOtrub", "WSZC_ShrapnelRagdollKeep")` с `timer.Simple(0)` и `(0.3)` |
| Стекло руками/ногами в ragdoll | `RagdollGlassShrapnel` вынесен из `WrapHook(..., pre)` в отдельный `hook.Add("Ragdoll Collide", "WSZC_GlassRagdoll", ...)`. `IsGlassCollision()` проверяет и `TheirSurfaceProps`, и браш-сущность (`func_breakable_surf`, `MAT_GLASS`, material name «glass»). Порог скорости 350→120, фильтр `DeltaTime >= 0.25` убран (это порог УРОНА ZCity, а не касания). `OwnerOf` добавлен fallback `GetNWEntity("ply")` |
| Боль и нарастающее кровотечение от ошибок мини-игры | C:U `BreakShrapnelGrasp()` пишет `state.bleed +0.4..1.0`, `state.pain +9..16`; `PushShadow` хранит `_WSZCExpectedBleed/Pain`, детектирует скачок на limb с `state.shrapnel > 0` и вызывает `WSZC.ApplyShrapnelComplication()`: `org.pain`, `org.bleed`, запись в `org.wounds` с boneName этой конечности (→ `LimbBleedMap`) и `org.wszc_shrapnel_irritation[limb]`. В `Org Think` irritation тиками добавляет bleed/pain, пока осколок не извлечён |
| Рука в шприце / курсор не мигает | `InputMouseApply` больше не `return true` (иначе `gui.MousePos()` замирал и рука не двигалась); `MINIGAME_ALLOWED_BINDS` пропускает `+attack`/`+attack2` (SetupMove всё равно обнуляет кнопки); `WSZC_MinigameCursorWatch` re-assert без проверки `vgui.CursorVisible()`; `WSZC_MinigameClientWatch` больше не сбрасывает курсор (grace 5 с только как страховка) |

Валидация: все 10 Lua-файлов проходят `luaparser`, `addon.json` — JSON-парсер,
headless-тесты `TEST_OK 11/11` (базовые фиксы), `TEST_OK 6/6` (full-screen),
`TEST_OK 20/20` (FX/кровь/курсор/камера/бинды), `TEST_OK 11/11` (источники
шрапнели/reset-guard) и `TEST_OK 7/7` (ragdoll-сохранение, `Fake`-хук, стекло
по брашу и surfaceprop, осложнение, нарастание, сброс при извлечении).
Живой GMod-сервер не запускался.
