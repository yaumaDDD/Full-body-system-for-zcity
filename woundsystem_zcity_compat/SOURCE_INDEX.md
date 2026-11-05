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
| Убрать ВСЕ эффекты C:U | `cl_zcity_woundsystem_compat_fx.lua` содержит точный список `hook.Remove`: `WoundSystem_PostProcess`, `StaminaEffects`, `BlindEffects`, `ChromaticAberration`, `SpinNausea*`, `Lobotomy*`, `BrainReverse*`, `DrawManualStatic`, `FullStatic`, `BlindVignette`, `VignetteVisuals`, `MoodlesPaint`, `SelfTalkHUDPaint`, `DrawMoodIcon`, `Unconscious*`, `EYEVIEW_CalcView`, `BlackSkybox`, world/sky fog, `BallisticAimKick`. **`DeathScreenDisplay` из списка исключён**: `WSZC.WrapCUDeathScreen()` заменяет его через `hook.Add`, выставляет `WSZC.CUDeathVisualsHidden` на время вызова (все обёрнутые draw-примитивы становятся no-op) и сохраняет ЛКМ → `WoundSystem_PlayerRespawnRequest` (`cl_health_gui.lua:5716`); иначе `sv_deathscreen.lua:WoundSystem_BlockRespawn` блокирует респавн навсегда. Запасной `WSZC_CUDeathRespawnFallback` шлёт тот же запрос, если хук отсутствует. **Не трогаются** `WoundDollAndPanel`, `WoundSystem_UIRegistry`, `ToggleHUDInput`, `WoundSystem_ScreenClickerWatchdog` — панель и курсор остаются. `TextCorruption.ShouldCorrupt/Corrupt` нейтрализованы; конвары `woundsys_pain_shader_enabled`, `moodles`, `nausea`, `visual_quality`, `self_talk` и др., а также аудио C:U выставляются в `0`. Оригиналы хуков сохраняются в `WSZC.CUFxSaved` и возвращаются при `zc_woundsystem_compat_disable_cu_fx 0`; фильтр повторяется раз в секунду |
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

## Вывихи, переломы, инвентарь C:U и панель unit

| Требование | Реализация |
|---|---|
| Мини-игра вправления костей вручную в WoundView | Родная `WoundSystemDislocationMinigame` (C:U `cl_dislocation.lua` + `Sessions.Dislocation` в `sv_health.lua`), кнопка `FIX DISLOCATION` из `WoundSystemDrawLimbActionPoint()`. `WSZC.SyncDislocation()`/`WSZC.RestoreBones()` в `sv_..._organism.lua` связывают `state.dislocated` с `org.*dislocation` **только на лимбе выше перелома**; успех снимает флаг всей группы (`DISLOC_FLAGS`, один лимб на флаг), пишет `org.painadd + 10` и `ply.fullsend`, а не откатывается shadow. Свежий вывих получает `state.dislocationTimer = WSZC.DislocationStartTimer()` (по умолчанию 35), прогресс сессии не перезаписывается |
| Вывих не теряется в ragdoll | `RestoreShrapnelSoon()` дополнительно зовёт `WSZC.RestoreBones()`; `SyncShrapnel()` теперь ВСЕГДА обновляет `ply._WSZCLimbsRef` (раньше `RestoreShrapnel` выходил раньше при пустом `org.wszc_shrapnel`, из-за чего игрок без осколков вечно выглядел «новым ragdoll» и вправление откатывалось) |
| Мини-игра проходима при боли | `WSZC.DislocationActive()` читает `WSZC.CUSessions.Dislocation[ply]`; на время сессии `body.avgPain` ограничен 60 (C:U `DislocationPainBlock = 75`), `ply.organism.pain` не меняется. `WSZC.MinigameActive()` на клиенте и `WSZC_MinigameServerLock` на сервере тоже знают про нативную сессию: курсор, frozen angles, нулевое движение |
| Переломы «как в ZCity» | `Fractured()` читает `org.<limb> >= 0.85` и `org.brokenribs > 0`, но **только на среднем лимбе** (`forearm_*`/`crus_*`) — см. №11; `PushShadow` пишет `state.broken`/`state.boneHealTimer`. Создание — ванильный `sv_bone.lua`, регенерация — `sv_pain.lua`, лечение — ZCity SWEP → `WSZC.ApplyMedicalDelta()`. Своей мини-игры и своей симуляции костей нет |
| Убрать инвентарь C:U | `cl_..._layout.lua`: прокси `WoundSystemInventorySlots` возвращает `{type="empty"}` для `1..5`, игнорирует запись в них и честно хранит слот `6`; `RequestInventoryMove` → no-op; снимаются `WoundSystem_WorldItemInput/WorldItemCheck/WorldItemDraw/BodyUseHeldItemInput`, гасится `WoundSystemDragState`. Конвар `zc_woundsystem_compat_hide_cu_inventory` |
| Убрать панель unit и инвентарь (runtime-фикс) | `WSZC.InstallCUHudFilter()` заменяет хук `WoundDollAndPanel` через `hook.Add(...)` (запись в `hook.GetTable()` была несостоятельна на сборках с копией таблицы); `WSZC.CUHudHiddenRegion()` + обёртки `draw.SimpleText`, `draw.RoundedBox`, `surface.DrawTexturedRect( Rotated )`, `surface.DrawRect`, **`surface.DrawOutlinedRect`**, `WoundSystemQueueLocaleTooltip`/`slot_*` direct-tooltip глушат зону `UNI-HEALTH` и 5 слотов. Зоны считаются с `woundsys_ui_scale` (0.6..1.6) и не глушат полноэкранный фон. **Дополнительно обёрнуты `surface.DrawTexturedRectUV`, `surface.DrawLine`, `surface.DrawPoly`, `surface.DrawText`, `draw.SimpleTextOutlined`** — именно ими C:U рисует зелёные полосы сканера, лёгкие, бицепс и ЭКГ, которые оставались слева после `e70bfb5`. `WSZC.CUDeathVisualsHidden` глушит ВСЕ примитивы на время хука экрана смерти (включая полноэкранный чёрный прямоугольник). `PreDrawHUD`/`PostDrawHUD` — запасной контур, включается только если обёртку хука установить не удалось. WoundView полностью не рисуется, пока активна мини-игра. Конвары `zc_woundsystem_compat_hide_unit_panel`, `zc_woundsystem_compat_hide_cu_inventory` |
| Скрыть предметы в руках | `PreDrawViewModel` / `PreDrawPlayerHands` возвращают `true`, Think один раз переключает `SetNoDraw` на viewmodel, пока `WSZC.MinigameActive()`. |
| Уменьшить вправление | `WSZC.WSZCMinigameActive()` / `WSZC.NativeMinigameActive()` разделяют полноэкранный клип (только WSZC бинт/шприц) и нативный клип C:U × `zc_woundsystem_compat_native_minigame_zoom 0.75`; `WSZC.DislocationStartTimer()` = 35 вместо 100 (`DislocationStartSpread = 5` → кость не улетает за верх экрана); `WSZC.AnyDislocation()` капит `avgPain` до старта сессии. |
| Кукла не обрублена фильтром HUD | `HiddenRegion()` гасил ВСЕ примитивы в зоне сканера/слотов, а кукла `unitmenu` шире родного квадрата 760 px → пропадали левая рука, ноги, иконки осколков и `REMOVE SHRAPNEL`. `WSZC.InstallMaterialTracker()` оборачивает `surface.SetMaterial` (устанавливается обоими Think-хуками всегда) и пишет `WSZC._DrawMaterialName`; `WSZC.IsDollDrawMaterial()` пропускает `wszc/unitmenu/limbs|status/*`, `casunknown-images/middle|outlines|icons/*`, `screen/uiPoint`. Сканер/слоты/`CUDeathVisualsHidden` по-прежнему гасятся. Размер куклы `0.28 → 0.24`. Нативный оверрайд руки переведён на общий трекер через `WSZC._OnSetMaterial` |
| Осколки от стекла кулаками | Кулаки `weapon_hands_sh.lua:1653` бьют `func_breakable_surf` через `TakeDamageInfo`, но `PostEntityTakeDamage` для браша приходит не всегда. `WSZC.TryGlassStrike()` вызывается и из `PostEntityTakeDamage` (`WSZC_GlassStrike`), и из нового `EntityTakeDamage` (`WSZC_GlassStrikePre`, `return nil` не блокирует урон); `glassCooldown` 0.5 с дедуплицирует. Игрок резолвится `OwnerOf(striker) or OwnerOf(attacker) or OwnerOf(inflictor)` — у SWEP-кулаков нет `.organism`. Не зависит от `shrapnel_only_shotgun_blast`. Лог при `zc_woundsystem_compat_organism_debug 1` |
| Кровь hemogen не тронута | `project hemogen blood.zip` = 123 файла без `materials/`; `advancedblood/sprites/*` и `advancedblood/decals/*` отсутствуют → ERROR-квадраты. compat не меняет ни один файл/хук/конвар аддона и не обращается к `advancedblood/*` |
| Две WSZC мини-игры на весь экран, нативные C:U — в авторском размере | `WSZC.ApplyFullscreenClip()` возвращает `0,0,ScrW(),ScrH(),0` для WSZC-игр; нативные C:U по умолчанию **НЕ** растягиваются: `zc_woundsystem_compat_fullscreen_native 0`, `zc_woundsystem_compat_native_minigame_zoom 1` → родной квадрат 760 px без shrink. `fullscreen_native 1` включает прежний `Clip.Scale()*NativeFullscreenK()` (live-регрессия: осколок 26×138 растягивался в огромный обрезанный спрайт, нижняя часть раны уходила за экран) |
| Белые пустые слоты и подложка action point | `HiddenRegion` разделён: `HiddenRegionRaw()` (без whitelist) для `DrawOutlinedRect`/`DrawRect`/`RoundedBox`/`DrawLine`/`DrawPoly`, `HiddenRegion()` (с whitelist) только для текстур и текста. Рамки слотов не имеют своего `SetMaterial` и раньше наследовали материал лимба |
| Бег после травмы / ресета | `RESET_KEEP` сокращён до `otrub/needotrub/fake/needfake/alive/otrub_start/unconscious`; `WSZC.ClearMovementPenalties()` сбрасывает `canmove`, `stun`, `pain`, `org.legs` в `hg.organism.Clear` (стоя и лёжа) и `WB.ResetOrganism` |
| Кукла с человеческими пропорциями, стандартный чёрный цвет и обводка по форме лимбов | `tools/build_unitmenu_materials.py`: запечённые позиции 15 слоёв давали широкое «пальто» с короткими ногами, поэтому введён явный `HUMAN_LAYOUT` (маленькая голова, узкий короткий торс, тонкие руки T-pose, длинные узкие ноги, компактные целые стопы, симметрия пар (вертикальные швы сняты с нативной куклы `Screenshot_2-10.png`)). Каждый слой обрезается по **жёсткому порогу alpha >96** (иначе `r_foot.png` с прозрачной левой половиной превращал стопу в полоску), масштабируется LANCZOS в свою ячейку **с отступом `EDGE_PAD_MIN=6`**, эрозия даёт тонкие зазоры суставов, а **обводка строится как `mask - MinFilter(mask, EDGE_WIDTH)` — по форме КАЖДОГО лимба**, как родные `casunknown-images/outlines/*`. Ни один белый пиксель не касается границы спрайта (assert `worst == 0.0`), поэтому «конструктор» из рамок невозможен. Единый `outer_band` и прямоугольные `seam_lines` удалены. Цвет `_fill` — **стандартный чёрный `(0,0,0)`** исходных слоёв архива; шифер `(42,56,60)` отклонён live. Анатомия `HUMAN_LAYOUT` сохранена, `native_tint`/`middle/*` не возвращались. `cl_..._layout.lua`: `IsDollLimbMaterial()` матчит ТОЛЬКО `*_fill.png` и ставит белый `SetDrawColor` (иначе C:U умножает на чёрный `finalMiddle`); `*_edge.png` намеренно НЕ перекрашивается, чтобы `finalOutline` + `HoverAnims` C:U продолжали затемнять обводку при наведении. Размеры спрайтов — степени двойки (C:U берёт `mat:Width()`, GMod округляет PNG до POT), боксы откалиброваны по `Screenshot_2-10.png`/`Screenshot_1-10.png`. 30 PNG + `wszc_unitmenu_geometry.lua` пересобраны; 15 id, hitbox'ы, `FIX DISLOCATION` / `REMOVE SHRAPNEL` не тронуты |
| Поиск `Limbs` не теряется в живом клиенте | `WSZC.FindCULimbs()` теперь кэширует результат, обходит upvalue-цепочку не только `WoundDollAndPanel`, но и `HUDPaint` / `HUDPaintBackground` / `PreDrawHUD` / все хуки, плюс экспортированные `WoundSystemClientState`, `WoundSystem.HealthGUI`, `WoundSystem.ClientState` (сканы через `pcall`, чтобы чужой `__pairs` не уронил HUD); `WSZC.ClearCULimbsCache()` для сброса. Дополнительно `PreDrawHUD` → `WSZC_UnitmenuDollRetry` раз в секунду повторяет `ApplyDoll`, пока патч не применён (C:U мог зарегистрировать хук позже нашего первого `Think`). Это ответ на расхождение: headless-композит показывал человеческую куклу, а live-скрин — широкое «пальто» |
| Лишний текст мини-игр; затемнение фона сохранено | `zc_woundsystem_compat_hide_minigame_text 1` + `WSZC.InstallMinigameTextFilter()` (вызывается из `WSZC_CUInventoryLayout`): `Clip.DrawHeader` перевызывается с `title/value/guide = ""` и `panelAlpha = 0` — убираются «Shrapnel extraction (1/5)», три строки инструкций и чёрная верхняя панель, но **иконка `data.mat` остаётся**; `Clip.DrawExitGuide` глушится, а **`Clip.DrawBackdrop` сохранён** (затемнение заднего фона); `draw.SimpleText`/`SimpleTextOutlined`/`DrawText` фильтруются ТОЛЬКО по `WSZC.IsMinigameTextFont()` (`MINIGAME_TEXT_BASES` = 3 chrome-шрифта + `WoundSystemAEDStatus`, суффикс `_<scale>` от `WoundSystemGetFont` снимается) И только пока `WSZC.MinigameTextHidden()` (активная мини-игра, включая `WoundSystemSelfHarmMinigame`). Поэтому ZCity `sh_notification.lua` (`BerserkFont`/`HuyFont`/`SmallHuyFont`/`ZB_ProotOSMedium`), `TechScanner*`/`CrunchyTech*`, красный death-текст, капли и `Icons.*` не трогаются, а AED-статус гасится только внутри мини-игры. `minigameshrapnel.png` — **передний слой раны** (`cl_shrapnel.lua:421`, `cl_syringe.lua:540`), а не чёрная панель; его подавление в `6e2196f` удалило «нижнюю часть, откуда достаётся осколок». Обёртка `surface.DrawTexturedRect` **удалена**; `WSZC.IsMinigameWoundLayer()` + `WSZC.IsMinigameGameplaySprite()` защищают рану, осколок, руку, пинцет, `bandageOuter`, `Icons.*` от HUD-фильтра. Конвар `0` возвращает исходный текст и панели |
| Рука без инерции | `WSZC.NativeHandCursorPos()` читает `gui.MousePos()`, `WSZC.PinNativeHandToCursor()` пишет `MG.handScreenX/Y` активной мини-игры, `HandRectForCursor()` использует реальный курсор вместо `cx,cy` от C:U. `zc_woundsystem_compat_hand_pin_cursor 0` — откат |
| Светлый фон WoundView | `HiddenRegionRaw()` для полноэкранного квада возвращает `cvHideWoundBackdrop:GetBool() and WoundSystemHealthHUDOpen == true`; unconscious-blackout при закрытом HUD сохраняется |
| Рука ровно на курсоре | `DrawTexturedRectRotated` получает центр = курсор. `WSZC.HandRectForCursor()` сдвигает центр на `(0.5-px)*nw`, `(0.5-py)*nh` (`hand_pivot_x 0.16`, `hand_pivot_y 0.45`), `rot=0`, ширина ≤ `hand_max_screen 0.34 * ScrW`. `MG.handDrawW/H` и хитбоксы не меняются |
| Курсор скрыт | `WSZC.SyncMinigameCursor()` → `vgui.GetWorldPanel():SetCursor("blank")` пока активна любая мини-игра,восстановление прежнего курсора при выходе; `gui.EnableScreenClicker` обёрнут для повторного применения. `zc_woundsystem_compat_hide_minigame_cursor 0` — откат |
| Убрать ERROR-материалы и сделать аддон самодостаточным | Исходный `casualites unknown.zip` = 71 Lua без `materials/`. `tools/pack_ui_materials.py` читает `origin/main:для переделывания интерфейса.zip` (216 PNG) и `origin/main:для того чтобы все работало вместе материалы для UI.zip` (362: `casunknown-images/*`, `woundsystem/*`, 7 `.vtf`, 6 `.vmt`) и вместе с 33 нарезанными PNG кладёт **647 файлов** в `woundsystem_zcity_compat/materials/`; `/tmp/build_packs.py` зеркалирует их в `garrysmod/addons/casualties_unknown_health_system_beta/materials/` full pack. Упаковщик парсит все Lua C:U+WSZC, собирает 125 путей материалов и создаёт 36 алиасов: 25 camelCase-копий (регистр на Linux), 11 переносов (`dislocationminigame`/`shrapnelminigame`/`syringeminigame` ← `bandageminigame`, `hemothoraxfill_red` ← `hemothoraxfill`). 14 loose-дублей проверены побайтово и пропущены. Финальный `assert` запрещает любой неразрешённый путь; отчёт — `MATERIALS.sha256`. Lua C:U не тронут (71 файл), звуков по-прежнему нет |
| Переделать интерфейс персонажа (куклу WoundView) по архиву | `origin/main:для переделывания интерфейса.zip` → `tools/build_unitmenu_materials.py` нарезает 15 слоёв 1500×1500 по alpha-bbox в `materials/wszc/unitmenu/limbs/<id>_fill.png` (стандартный чёрный силуэт) + `<id>_edge.png` (тонкая белая обводка по форме КАЖДОГО лимба, вписанная с отступом, НЕ рамка вокруг спрайта), иконки `status/*` уменьшает до 32×32; геометрия (`cx`, `cy`, `w`, `h`) пишется в `wszc_unitmenu_geometry.lua`. Маппинг: `thorax=chest`, `abdomen=pelvis`, `*_R→l_*`, `*_L→r_*`. В рантайме `WSZC.FindCULimbs()` обходит upvalue-цепочку хука `WoundDollAndPanel` (включая наш `hudWrapper`) через `debug.getupvalue`, а `WSZC.ApplyUnitmenuDoll()` мутирует таблицу НА МЕСТЕ: `matM/matO`, `ox=(cx-750)*k`, `oy=(cy-750)*k`, `size=k`, `sourceW/sourceH=w/h`, `texturePadding=0`, `flip=false`. Идентификаторы 15 лимбов, `PlayerLimbs`, hover-hitbox, `limbScreenPoints`, `FIX DISLOCATION` и `REMOVE SHRAPNEL` не меняются. `WSZC.ApplyUnitmenuIcons()` подменяет глобальные `Icons.fracture/fracture2/dislocate/*bleed*`; `WSZC.RestoreUnitmenuDoll()` откатывает при `unitmenu_doll 0`. Конвар `zc_woundsystem_compat_unitmenu_scale 0.24` |
| Переделать руку в мини-играх по архиву | `WSZC.UnitmenuHandMat(clicked)` → `homigrad/handanim/hand.png` (ладонь) / `3_3.png` (кулак); `WSZC.UnitmenuHandGeometry()` → 960×540, pivot `(0.12, 0.5)` у кончиков пальцев, `WSZC.UnitmenuHandAlpha()` → 255, `WSZC.UnitmenuHandAngle()` гасит поворот 290° до 1/4. `wszc_cl_bandage.lua` / `wszc_cl_syringe.lua` читают эти хелперы (в шприце ещё `_unitmenuPivotX/Y` и нулевой idle-угол). Для НАТИВНЫХ C:U игр (dislocation/shrapnel/AED/бинты) код которых лежит в неизменном ZIP, `WSZC.InstallNativeHandOverride()` узко оборачивает `surface.SetMaterial` (только `handgrasp*idle1*` / `handgrasp*click*`, не wrench/tweezers/selfharm) и `DrawTexturedRectRotated`/`DrawTexturedRect`: меняется материал и прямоугольник ОТРИСОВКИ, но НЕ `MG.handDrawW/H`, т.е. все хитбоксы остаются на месте. Вне нативной мини-игры оверрайд инертен. Если WIP-аддон с кадрами отсутствует — автоматический откат на руку C:U. Конвар `zc_woundsystem_compat_handanim_scale 0.55` |
| Стабилизировать руку/курсор | `WSZC.StabilizeHandPhysics()` обнуляет `pain`/`shakeX`/`shakeY` и ограничивает `maxLength=45` в копиях `sh_handphysics.lua`; `WSZC.HandCursorScale()` = 0.45 умножает спрайт 512×1260 в `wszc_cl_bandage.lua` / `wszc_cl_syringe.lua`; `WSZC.MinigameActive()` теперь знает все нативные мини-игры C:U (курсор + лок камеры). |
| Респавн после смерти | `WSZC.MinigameContextOK()` возвращает `false` для `not LocalPlayer():Alive()`; `WSZC.MinigameActive()` / `WSZCMinigameActive()` / `NativeMinigameActive()` всё проверяют. `WSZC.ClearAllMinigameState()` на `PlayerDeath`/`PlayerSpawn` сбрасывает `MinigameHUDOpen`, `MinigameFrozenAngles`, `_ViewModelHidden` и `MG.active` у всех 7 таблиц мини-игр. Серверный `WSZC_MinigameServerLock` выходит сразу для мёртвого игрока, чтобы `PlayerDeathThink` получил свободный `CUserCmd`. |

Валидация: все 11 Lua-файлов проходят `luaparser`, `addon.json` — JSON-парсер,
headless-тесты `TEST_OK 11/11` (базовые фиксы), `TEST_OK 8/8` (full-screen и
нативный клип), `TEST_OK 20/20` (FX/кровь/курсор/камера/бинды), `TEST_OK 11/11`
`tools/tests/test_wszc_regression.py` — **65 проверок** в репозитории:
статические маркеры всех прошлых фиксов, `ALL_LUA_OK 11/11`,
`CJK_CLEAN`, PIL-проверка человеческих пропорций / белой обводки /
зазоров суставов, 647 материалов, `MATERIALS.sha256`, оба ZIP /
зеркало / `MANIFEST.txt` и 29 рантайм-проверок на lupa (включая
точечный фильтр текста (включая AED), сохранение уведомлений ZCity,
сохранение `finalOutline` для hover и `FindCULimbs` fallback).
Прежние transient-наборы из `/tmp` не
пережили очистку песочницы; сборка тоже перенесена в
`tools/build_packs.py`.
Живой GMod-сервер ассистентом не запускался; правки сделаны по пользовательским
live-скриншотам.

## По live-скриншотам №6 (`Screenshot_2-8`, `Screenshot_3-5`)

### По live-скриншотам №6: пять исправлений (`Screenshot_2-8`, `Screenshot_3-5`)

| Претензия | Что было не так | Исправление |
| --- | --- | --- |
| «рукой двигать не могу в бандаже» | `InputMouseApply` и `SetupMove` вызывали `cmd:SetMouseX(0)` / `SetMouseY(0)`. При `gui.EnableScreenClicker(true)` GMod питает `gui.MousePos()` из того же `CUserCmd` mouse delta — обнуление прибивало курсор к `(0,0)`, и `HandPhysics.Step()` видел нулевую цель. | Оба сеттера удалены. Заморозка камеры (`SetViewAngles`), нулевое движение/кнопки и `return nil` сохранены. Мышь доходит и до VGUI-курсора, и до мини-игры. |
| «я осколок рожаю или че, где нижняя часть откуда он достается?» | `minigameshrapnel.png` ошибочно сочли чёрной панелью и подавляли в `surface.DrawTexturedRect`; это **передний слой раны** (`cl_shrapnel.lua:421`, `cl_syringe.lua:540`). Плюс `fullscreen_native 1` умножал `Clip.Scale()` на `NativeFullscreenK()` до 2.2×, растягивая осколок 26×138 в огромный обрезанный спрайт и уводя низ раны за экран. | Подавление удалено полностью; добавлены `WSZC.IsMinigameWoundLayer()` и белый список `WSZC.IsMinigameGameplaySprite()` (рана, осколок, рука, пинцет, `bandageOuter`, `Icons.*`) в HUD-фильтре. `fullscreen_native` по умолчанию `0`, `native_minigame_zoom` `1` → авторский квадрат 760 px. `text=all` убирает только заголовки/инструкции/чёрный chrome. |
| «почему шрапнель пропадает при вставании из рагдолла» | `RESET_KEEP` не содержал `wszc_shrapnel*`, поэтому `hg.organism.Clear()` стирал тень; а `PlayerSpawn` безусловно занулял organism и C:U limbs, перебивая `RestoreShrapnelSoon` (0/0.3 с) из-за неопределённого порядка хуков. | Три поля добавлены в `RESET_KEEP`; `CarryShrapnelShadow()`/`RestoreShrapnelShadow()` переживают и ветку `down=false`; `hook.Add("Fake"/"FakeUp"/"HG_OnWakeOtrub")` ставит `_WSZCRagdollTransitionUntil`; `WSZC.ReconcileSpawnShrapnel()` при переходе **восстанавливает** из авторитетного organism, а чистит C:U только на настоящем респавне. `SyncShrapnel()` больше не копирует свежую пустую таблицу limbs обратно в organism в том же тике. |
| «сделай wound view куклу не таким цветом, верни стандартный и обводку по краям тоже» | `(42,56,60)` + единый `outer_band` + прямоугольные `seam_lines` — отклонено live. | Выбор владельца: **`black_anatomy` + `native_outline`**. `_fill` = стандартный чёрный `(0,0,0)` исходных слоёв архива; `_edge` = тонкая линия по форме **каждого** лимба (`mask - MinFilter(mask, 9)`), вписанная с `EDGE_PAD_MIN=6`, поэтому ноль белых пикселей на границах спрайтов. Наша `HUMAN_LAYOUT` сохранена; `native_tint`/`middle/*`/`1da8b4a`/`b47a0cb`/рамки не возвращались. Hover `finalOutline`/`HoverAnims` сохранён. |
| «почему когда я нажимаю на пустую область wound view окно не закрывается» | В самом C:U нет generic outside-click close: `CloseHealthHUD()` зовётся только по клавише, смерти и респавну; `GUIState` — local `:1702`. | Добавлено новое WSZC-поведение: `WSZC.WoundViewEmptyClick(mx,my,s)` + `Think`-хук `WSZC_WoundViewEmptyClickClose` по переднему фронту ЛКМ вызывает `WoundSystem.CloseHealthHUD()`. Исключены кукла, 5 слотов, кнопки инструментов, action point, UNI-HEALTH, тултипы, drag, активная мини-игра, внешние меню и фокус ввода. Откат: `zc_woundsystem_compat_close_on_empty_click 0`. |

Все пять правок проверены headless (71+ проверок, `ALL_LUA_OK`, пересборка материалов и обоих ZIP), но **живой GMod агентом не запускался** — принятие только по свежим live-скриншотам.

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

3. **Рука убрана, курсор стандартный.** `hand=archive` ОТМЕНЕНО по запросу
   «убери руку из мини игр замени на стандартный курсор». Конвары по
   умолчанию: `zc_woundsystem_compat_hide_minigame_cursor 0` (видна обычная
   стрелка, никакого `blank`), `zc_woundsystem_compat_hide_minigame_hand 1`,
   `zc_woundsystem_compat_handanim 0`, `zc_woundsystem_compat_hand_pin_cursor 0`.
   `WSZC.UnitmenuHandAlpha()` возвращает `0`, поэтому наши копии бинта/шприца
   сохраняют ВСЕ хитбоксы и вызовы отрисовки, но руку не видно;
   `WSZC.InstallNativeHandOverride()` теперь ставится и в этом режиме и
   подавляет нативные `handgrasp*` спрайты через флаг `handHide`. Пин к курсору
   и inertia-подмена отключены — стрелка всегда там, где реальная мышь.

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
