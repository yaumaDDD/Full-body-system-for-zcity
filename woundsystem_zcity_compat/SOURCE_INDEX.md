# Исходный код коннектора

Аддон полностью состоит из открытого Lua-кода; бинарных/скомпилированных
модулей нет. Все файлы лежат в `lua/autorun/` и загружаются штатным порядком
GMod. Исходные ZIP-аддоны не изменяются: всё патчится в рантайме. Исключение —
одна строка `Not completed - nothing was applied` в `sv_woundbridge.lua`,
которая убрана только внутри пересобранного `zcity_full_pack.zip` как дублёр
рантайм-фильтра (см. ниже).

| Файл | Сторона | Что делает |
|---|---|---|
| `lua/autorun/sh_zcity_woundsystem_compat.lua` | shared | `WSZC.OrganismAuthority()`, конвар `zc_woundsystem_compat_authority`, `WithVanillaContext`, `PatchIsEnabled`, `PatchIsBridged`; `InstallAmputationStatus()` регистрирует отдельный `WSZC_AMPUTATION` (`order=-10000`) для proximal stump |
| `lua/autorun/server/sv_zcity_woundsystem_compat.lua` | server | Основной мост: weak-key `WSZC.RawDamage`, `DamageWrapper`, снимки/дельты медицины в `ApplyItemToBodyImpl`, публикация `WSZC_Ready` / `WSZC_OrganismAuthority`, `Setup()`/`Attempt()`, mode-aware `InstallOrganismMode` |
| `lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua` | server | Authority-слой `ply.organism`: shrapnel/shotgun/glass, per-limb shadow, bones и медицина. Полный бинт закрывает external shrapnel-рану; отдельный infection timer ведёт конечность→торс→мозг→death (240/420/600 с). `Start/Tick/CompleteShrapnelAftercare()` создают и закрывают отдельную extraction-рану только финальным бинтом. `BandageSeverityPerFullEffect()` — общая формула лечения и ZCity-стоимости; `BandageSeverityOnLimb()` измеряет реальный до/после расход. `SyncAmputationShadow()` сохраняет родную анатомию forearm+hand / crus+foot и отдельный stump-статус; `BestTourniquetLimb()` даёт реально кровоточащей ампутации приоритет над artery только для жгута; `BestBandageLimb()` выбирает реальные ordinary wounds/aftercare и игнорирует stale C:U `isBandaged` и shadow-only bleed. `SnapshotRagdollOrganism()` сохраняет весь organism при `Fake Up + OverrideSpawn`, а explicit reset/respawn очищает его. `InstallResetStructureGuard()`, `DisableCUBloodReplacement()`, 5-секундный reapply |
| `lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua` | server | instant/watchdog/continuous мини-игры, слот `6`, net-протокол, movement/camera lock. `StartShrapnelUnwrap()` создаёт виртуальный reverse-bandage без расхода предмета; только 360° вызывают снятие повязки. Для authority ZCity-бинта `NativeBandageContext` получает SWEP/idx/def и native `appliedLive`; `ProcessNativeBandageInput()` ограничивает лечение реальной severity и остатком `modeValues`, списывает ровно `treated`, отражает заряд в virtual slot через `maxDur/def`, сохраняет штатный `onClose/AfterUse`, не вызывает второй `onProgress/Consume` и при нулевом ordinary bleed/aftercare завершает native-сессию `completed` с удалением virtual slot/client overlay. Клиент не предсказывает старые `100/12`: slot обновляется только авторитетным пакетом. Operator и patient разделены: conscious `FakeRagdoll/fake` не закрывает игру, death/otrub/низкое consciousness закрывает; `OverrideSpawn` отличает FakeUp от настоящего respawn force-close |
| `lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua` | client | Full-screen мини-игры: `WoundSystem.MinigameClip.GetRect()`, `WSZC.MinigameScale()`, кламп adrenaline/painkiller; регистрация amputation moodle через native `Reg()`, `MinigameContextOK()` разрешает conscious ragdoll, но запрещает death/otrub/потерю сознания; общий hand scale `0.55` в C:U/WSZC, migration `6`, общий `PinMinigameHandToCursor()` синхронизирует cursor/gameplay/pivot; native centre/pivot/rotation/hitbox сохранены |
| `lua/autorun/client/cl_zcity_woundsystem_compat_fx.lua` | client | Фильтр эффектов C:U: снимает `RenderScreenspaceEffects`/`CalcView`/`HUDPaint*`/`PostDrawHUD`/`CreateMove`/fog-хуки и blood-хуки, нейтрализует `TextCorruption`, выставляет визуальные конвары C:U в `0`, умеет восстанавливать оригиналы |
| `lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua` | client | Пункт «Проверить травмы» в круговом меню ZCity → `WoundSystem.OpenHealthHUD()`, gate `WSZC_Ready`, `OPEN_DELAY = 0.12`, `wszc_open_wounds` |
| `lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua` | client | Клиентская часть мини-игр, приём `WSZC_*`, cursor/view/input lock, блокировка движения `SetupMove`; cursor watchdog завершает refresh через `SyncMinigameCursor()` и не ставит `arrow` поверх активной руки; `PlayerSpawn` сохраняет conscious FakeUp, а настоящий respawn дополнительно force-close сервером |
| `lua/autorun/client/wszc_cl_bandage.lua` | client | Порт родной C:U мини-игры бинтования (ЛКМ/ПКМ/ESC), layout на весь экран; режим `unwrap` зеркалит угловой ввод, рисует `UNWRAP N%` и стандартную infection-иконку. Общий hand scale `0.55`; CU centre/pivot/rotation и gameplay hitbox не меняются |
| `lua/autorun/client/wszc_cl_syringe.lua` | client | Порт родной C:U мини-игры шприца (ЛКМ/ПКМ/ESC), board = весь экран, оффсеты в долях viewport |
| `addon.json` | мета | `title`, `type: ServerContent`, ignore `*.md`/`*.txt` |
| `README.md` | доку | Установка, подписки Мастерской, таблицы предметов/шрапнели, конвары, диагностика, ограничения |

## Ключевые решения

* `ply.organism` (ZCity) — единственный источник истины о здоровье.
* C:U остаётся UI, мини-играми, «теневыми» метриками и протоколом шрапнели;
  `woundsys_enabled` не выключается.
* Gunshot/blast хуки C:U подавлены, их правила перенесены в единый
  `WSZC.InjectDamageShrapnel`; стекло — единственный новый источник.
* `state.shrapnel` без поля `source`, без второй мини-игры извлечения; лимит 5 из
  `WoundSystem.Health.Constants.ShrapnelPieceCount`. Reverse unwrap — отдельный
  режим WSZC bandage, после него используется тот же native extraction.
* Полное лечение covered shrapnel только `unwrap 360° → extract → re-bandage`;
  внешняя кровь под бинтом нулевая, инфекция продолжается до финальной повязки.
* Рука во всех мини-играх использует общий визуальный scale `0.55`, без старого
  двойного `0.45 × 0.55`; cursor watchdog никогда не восстанавливает `arrow`
  во время активной hand-pointer мини-игры.
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
| Дробовик в ногу → кровь на всех 16 лимбах | `PushShadow` писал один глобальный `org.bleed` в КАЖДЫЙ C:U limb | `LimbBleedMap()` читает `org.wounds[n][4]` (имя кости) и `org.arterialwounds[n][7]` (`rlegartery` и т.п.), мапит в limb id; внутреннее кровотечение остаётся в `body.internalBleeding` |
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
| `reset organism` не встаёт | `InstallResetStructureGuard()` оборачивает `hg.organism.Clear` и `WB.ResetOrganism`: `WB.RestoreRagdoll` временно заменяется no-op. Explicit reset возвращает только down-структуру, очищая медицину, movement penalties и забытый native-кодом `brokenribs`; внутренний `Fake Up + OverrideSpawn` cycle-safe восстанавливает весь organism. Обычный respawn идёт очищающей веткой. Повторно шлются `hg.send_organism`/`hg.send_bareinfo` и обновляется shadow. Конвар `zc_woundsystem_compat_preserve_reset_structure` |
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
| Уменьшить вправление | `WSZC.WSZCMinigameActive()` / `WSZC.NativeMinigameActive()` разделяют полноэкранный клип (только WSZC бинт/шприц) и нативный клип C:U × `zc_woundsystem_compat_native_minigame_zoom 0.85`; `WSZC.DislocationStartTimer()` = 35 вместо 100 (`DislocationStartSpread = 5` → кость не улетает за верх экрана); `WSZC.AnyDislocation()` капит `avgPain` до старта сессии. |
| Кукла не обрублена фильтром HUD | `HiddenRegion()` гасил ВСЕ примитивы в зоне сканера/слотов, а кукла `unitmenu` шире родного квадрата 760 px → пропадали левая рука, ноги, иконки осколков и `REMOVE SHRAPNEL`. `WSZC.InstallMaterialTracker()` оборачивает `surface.SetMaterial` (устанавливается обоими Think-хуками всегда) и пишет `WSZC._DrawMaterialName`; `WSZC.IsDollDrawMaterial()` пропускает `wszc/unitmenu/limbs|status/*`, `casunknown-images/middle|outlines|icons/*`, `screen/uiPoint`. Сканер/слоты/`CUDeathVisualsHidden` по-прежнему гасятся. Размер куклы `0.28 → 0.24`. Нативный оверрайд руки переведён на общий трекер через `WSZC._OnSetMaterial` |
| Осколки от стекла кулаками | Кулаки `weapon_hands_sh.lua:1653` бьют `func_breakable_surf` через `TakeDamageInfo`, но `PostEntityTakeDamage` для браша приходит не всегда. `WSZC.TryGlassStrike()` вызывается и из `PostEntityTakeDamage` (`WSZC_GlassStrike`), и из нового `EntityTakeDamage` (`WSZC_GlassStrikePre`, `return nil` не блокирует урон); `glassCooldown` 0.5 с дедуплицирует. Игрок резолвится `OwnerOf(striker) or OwnerOf(attacker) or OwnerOf(inflictor)` — у SWEP-кулаков нет `.organism`. Не зависит от `shrapnel_only_shotgun_blast`. Лог при `zc_woundsystem_compat_organism_debug 1` |
| Кровь hemogen не тронута | `project hemogen blood.zip` = 123 файла без `materials/`; `advancedblood/sprites/*` и `advancedblood/decals/*` отсутствуют → ERROR-квадраты. compat не меняет ни один файл/хук/конвар аддона и не обращается к `advancedblood/*` |
| Две WSZC мини-игры на весь экран, нативные C:U — в авторском размере | `WSZC.ApplyFullscreenClip()` возвращает `0,0,ScrW(),ScrH(),0` для WSZC-игр; нативные C:U по умолчанию **НЕ** растягиваются: `zc_woundsystem_compat_fullscreen_native 0`, `zc_woundsystem_compat_native_minigame_zoom 0.85` → квадрат 646 px вместо 760 px; `zoom 1` возвращает исходный размер. `fullscreen_native 1` включает прежний `Clip.Scale()*NativeFullscreenK()` (live-регрессия: осколок 26×138 растягивался в огромный обрезанный спрайт, нижняя часть раны уходила за экран) |
| Белые пустые слоты и подложка action point | `HiddenRegion` разделён: `HiddenRegionRaw()` (без whitelist) для `DrawOutlinedRect`/`DrawRect`/`RoundedBox`/`DrawLine`/`DrawPoly`, `HiddenRegion()` (с whitelist) только для текстур и текста. Рамки слотов не имеют своего `SetMaterial` и раньше наследовали материал лимба |
| Бег после травмы / ресета | `RESET_KEEP` сокращён до `otrub/needotrub/fake/needfake/alive/otrub_start/unconscious`; `WSZC.ClearMovementPenalties()` сбрасывает `canmove`, `stun`, `pain`, `org.legs` в `hg.organism.Clear` (стоя и лёжа) и `WB.ResetOrganism` |
| Кукла с человеческими пропорциями, стандартный чёрный цвет и обводка по форме лимбов | `tools/build_unitmenu_materials.py`: запечённые позиции 15 слоёв давали широкое «пальто» с короткими ногами, поэтому введён явный `HUMAN_LAYOUT` (маленькая голова, узкий короткий торс, тонкие руки T-pose, длинные узкие ноги, компактные целые стопы, симметрия пар (вертикальные швы сняты с нативной куклы `Screenshot_2-10.png`)). Каждый слой обрезается по **жёсткому порогу alpha >96** (иначе `r_foot.png` с прозрачной левой половиной превращал стопу в полоску), масштабируется LANCZOS в свою ячейку **с отступом `EDGE_PAD_MIN=6`**, эрозия даёт тонкие зазоры суставов, а **обводка строится как `mask - MinFilter(mask, EDGE_WIDTH)` — по форме КАЖДОГО лимба**, как родные `casunknown-images/outlines/*`. Ни один белый пиксель не касается границы спрайта (assert `worst == 0.0`), поэтому «конструктор» из рамок невозможен. Единый `outer_band` и прямоугольные `seam_lines` удалены. Цвет `_fill` — **стандартный чёрный `(0,0,0)`** исходных слоёв архива; шифер `(42,56,60)` отклонён live. Анатомия `HUMAN_LAYOUT` сохранена, `native_tint`/`middle/*` не возвращались. `cl_..._layout.lua`: `IsDollLimbMaterial()` матчит ТОЛЬКО `*_fill.png` и ставит белый `SetDrawColor` (иначе C:U умножает на чёрный `finalMiddle`); `*_edge.png` намеренно НЕ перекрашивается, чтобы `finalOutline` + `HoverAnims` C:U продолжали затемнять обводку при наведении. Размеры спрайтов — степени двойки (C:U берёт `mat:Width()`, GMod округляет PNG до POT), боксы откалиброваны по `Screenshot_2-10.png`/`Screenshot_1-10.png`. 32 limb PNG + 3 status PNG + `wszc_unitmenu_geometry.lua` пересобраны; 16 id, hitbox'ы, `FIX DISLOCATION` / `REMOVE SHRAPNEL` работают в native C:U |
| Поиск `Limbs` не теряется в живом клиенте | `WSZC.FindCULimbs()` теперь кэширует результат, обходит upvalue-цепочку не только `WoundDollAndPanel`, но и `HUDPaint` / `HUDPaintBackground` / `PreDrawHUD` / все хуки, плюс экспортированные `WoundSystemClientState`, `WoundSystem.HealthGUI`, `WoundSystem.ClientState` (сканы через `pcall`, чтобы чужой `__pairs` не уронил HUD); `WSZC.ClearCULimbsCache()` для сброса. Дополнительно `PreDrawHUD` → `WSZC_UnitmenuDollRetry` раз в секунду повторяет `ApplyDoll`, пока патч не применён (C:U мог зарегистрировать хук позже нашего первого `Think`). Это ответ на расхождение: headless-композит показывал человеческую куклу, а live-скрин — широкое «пальто» |
| Живой 1111 сделан по 2222 точно, без «чуть больше» | `WSZC.UnitmenuReferenceDollTransform()` при convar `0.25` фиксирует итоговый `S=0.4155` и centreY `558.2` на 1365×1079, компенсируя сохранённый `woundsys_ui_scale` (0.6/1.0/1.25/1.6) и native centreY. Это устраняет живой S=0.469 из 1111 без изменения `REFERENCE_BOXES`. Для head/abdomen/thigh/crus/foot добавлен внешний `MaxFilter(9)`; thorax/arms/forearms/hands/neck не получают второй слой. S53f закрепляет внешние white-anchors 2222, R40 — неизменность экранного transform при разных UI scale |
| Убран ложный `disinfected/processing`, контур не ступенчатый | `WSZC.InstallDisinfectedIconFilter()` патчит private native `AddHudIcon` и пропускает ТОЛЬКО `Icons.disinfected` до добавления в icon list; infection/bleed/fracture и gameplay `disinfectTime` сохраняются. Generator добавляет `EDGE_AA_RADIUS=0.45` (neck исключён ради pinned seam), а HUD wrapper ставит LINEAR min/mag только на время native WoundView и восстанавливает оба filter stack после `pcall`. Pinned geometry, crop-first calibration, hitboxes и швы не меняются |
| Лишний текст мини-игр; затемнение фона сохранено | `zc_woundsystem_compat_hide_minigame_text 1` + `WSZC.InstallMinigameTextFilter()` (вызывается из `WSZC_CUInventoryLayout`): `Clip.DrawHeader` перевызывается с `title/value/guide = ""` и `panelAlpha = 0` — убираются «Shrapnel extraction (1/5)», три строки инструкций и чёрная верхняя панель, но **иконка `data.mat` остаётся**; `Clip.DrawExitGuide` глушится, а **`Clip.DrawBackdrop` сохранён** (затемнение заднего фона); `draw.SimpleText`/`SimpleTextOutlined`/`DrawText` фильтруются ТОЛЬКО по `WSZC.IsMinigameTextFont()` (`MINIGAME_TEXT_BASES` = 3 chrome-шрифта + `WoundSystemAEDStatus`, суффикс `_<scale>` от `WoundSystemGetFont` снимается) И только пока `WSZC.MinigameTextHidden()` (активная мини-игра, включая `WoundSystemSelfHarmMinigame`). Поэтому ZCity `sh_notification.lua` (`BerserkFont`/`HuyFont`/`SmallHuyFont`/`ZB_ProotOSMedium`), `TechScanner*`/`CrunchyTech*`, красный death-текст, капли и `Icons.*` не трогаются, а AED-статус гасится только внутри мини-игры. `minigameshrapnel.png` — **передний слой раны** (`cl_shrapnel.lua:421`, `cl_syringe.lua:540`), а не чёрная панель; его подавление в `6e2196f` удалило «нижнюю часть, откуда достаётся осколок». Обёртка `surface.DrawTexturedRect` **удалена**; `WSZC.IsMinigameWoundLayer()` + `WSZC.IsMinigameGameplaySprite()` защищают рану, осколок, руку, пинцет, `bandageOuter`, `Icons.*` от HUD-фильтра. Конвар `0` возвращает исходный текст и панели |
| Рука реально привязана к курсору по умолчанию | Общий `WSZC.PinMinigameHandToCursor()` каждый Think записывает `gui.MousePos()` в `handScreenX/Y`, обнуляет spring velocity/accumulator. `InstallNativeHandPhysicsPin()` находит private `HandPhysics` в upvalue native Think-хуков и заменяет spring-шаг синхронизацией ДО gameplay hitbox; WSZC bandage/syringe используют тот же helper напрямую. По умолчанию `hand_pin_cursor 1`, `0` вызывает оригинальную C:U HandPhysics |
| Светлый фон WoundView | `HiddenRegionRaw()` для полноэкранного квада возвращает `cvHideWoundBackdrop:GetBool() and WoundSystemHealthHUDOpen == true`; unconscious-blackout при закрытом HUD сохраняется |
| Пальцы, gameplay grip и системный курсор совпадают | `WSZC.HandRectAtPivot()` вычисляет центр как `target - R((0.4-0.5)*w, (0.1-0.5)*h)` с поворотом C:U `RotateLocal()`. В pin-режиме target — сам `gui.MousePos()`, а WSZC bandage/syringe не применяют developer offset `100/400`, spring inertia или collision clamp; orbit/grab/injection читают ту же `handScreenX/Y`. `0` возвращает прежние HandPhysics и offsets. Двойного `0.45 × 0.55` и screen cap нет |
| Рука вместо системного курсора без мерцания | `WSZC.SyncMinigameCursor()` ставит VGUI `blank` только пока активна мини-игра и видна рука; `EnableMinigameClicker()` теперь тоже вызывает Sync вместо периодического `RestoreMinigameCursor()`/`arrow`. Hand draw и watchdog удерживают один режим; на выходе и при `hide_minigame_hand 1` восстанавливается `arrow`. `hide_minigame_cursor 0` — показать стрелку вместе с рукой |
| Убрать ERROR-материалы и сделать аддон самодостаточным | Исходный `casualites unknown.zip` = 71 Lua без `materials/`. `tools/pack_ui_materials.py` читает `origin/main:для переделывания интерфейса.zip` (216 PNG) и `origin/main:для того чтобы все работало вместе материалы для UI.zip` (362: `casunknown-images/*`, `woundsystem/*`, 7 `.vtf`, 6 `.vmt`) и вместе с 37 сгенерированными PNG кладёт **651 файл** в `woundsystem_zcity_compat/materials/`; `tools/build_packs.py` зеркалирует их в `garrysmod/addons/casualties_unknown_health_system_beta/materials/` full pack. Упаковщик парсит все Lua C:U+WSZC, собирает 127 путей материалов и создаёт 36 алиасов: 25 camelCase-копий (регистр на Linux), 11 переносов (`dislocationminigame`/`shrapnelminigame`/`syringeminigame` ← `bandageminigame`, `hemothoraxfill_red` ← `hemothoraxfill`). 14 loose-дублей проверены побайтово и пропущены. Финальный `assert` запрещает любой неразрешённый путь; отчёт — `MATERIALS.sha256`. Lua C:U не тронут (71 файл), звуков по-прежнему нет |
| Переделать интерфейс персонажа (куклу WoundView) по архиву | `origin/main:для переделывания интерфейса.zip` → `tools/build_unitmenu_materials.py` нарезает 15 слоёв 1500×1500 по alpha-bbox в `materials/wszc/unitmenu/limbs/<id>_fill.png` (стандартный чёрный силуэт) + `<id>_edge.png` (тонкая белая обводка по форме КАЖДОГО лимба, вписанная с отступом, НЕ рамка вокруг спрайта), иконки `status/*` уменьшает до 32×32; геометрия (`cx`, `cy`, `w`, `h`) пишется в `wszc_unitmenu_geometry.lua`. Маппинг: `thorax=chest`, `abdomen=pelvis`, `*_R→l_*`, `*_L→r_*`. В рантайме `WSZC.FindCULimbs()` обходит upvalue-цепочку хука `WoundDollAndPanel` (включая наш `hudWrapper`) через `debug.getupvalue`, а `WSZC.ApplyUnitmenuDoll()` мутирует таблицу НА МЕСТЕ: `matM/matO`, `ox=(cx-750)*dollSize`, `oy=(cy-750)*dollSize+centreOY`, `size=dollSize`, `sourceW/sourceH=hoverW/hoverH`, `texturePadding=0`, `flip=false`; `dollSize/centreOY` вычисляются canonical 2222-transform, а не копируют сырой convar. Идентификаторы 15 исходных лимбов сохраняются; 16-й `neck` добавляется в те же native `PlayerLimbs`, hover-hitbox, `limbScreenPoints`, `FIX DISLOCATION` и `REMOVE SHRAPNEL`. `WSZC.ApplyUnitmenuIcons()` подменяет глобальные `Icons.fracture/fracture2/dislocate/*bleed*`; `WSZC.RestoreUnitmenuDoll()` откатывает при `unitmenu_doll 0`. Конвар `zc_woundsystem_compat_unitmenu_scale 0.25` |
| Отдельная интерактивная шея, как на эталонном скриншоте | `HEAD_SOURCE_LAYOUT` масштабирует исходный head один раз; `HUMAN_LAYOUT.head/neck` только разрезают этот общий силуэт, поэтому независимого второго resize нет. `cl_..._layout.lua`: `EnsureNeckLimb` копирует native action point в `Limbs` сразу после head, `EnsureNeckClientState` заполняет `GUIState.HoverAnims/LastHoverStates` и `PlayerLimbs.neck`, hit-test использует видимый `hoverW/H`, а `PostDrawHUD` рисует `Neck / Skin: N% / Muscle: N%`. `sv_..._organism.lua`: `InitPlayer` wrapper + отдельный `PlayerSpawn` timer + initial force-sync создают шею с первой жизни; `org.skull`, `Bip01_Neck1`, `neckartery` и skull-treatment маршрутизируются на neck. `head.dmg` удалён, `RagdollDamageBones` разделяет Head1/Neck1, moodle — `Broken neck`. Отключение doll удаляет добавленный neck из native `Limbs`, но не удаляет серверное медицинское состояние. ZCity HUD, таймер и нижние слоты не переопределяются |
| Компактная человеческая рука в мини-играх | `tools/build_minigame_hand.py` поворачивает реальные `homigrad/handanim/hand.png` / `3_3.png` на 75° и создаёт `wszc/minigame/hand_idle.png` / `hand_click.png` на исходном canvas 512×1260. `UnitmenuHandGeometry()` использует native pivot `(0.4,0.1)` и общий scale `0.55`; bandage/syringe сохраняют idle/hold rotation. `InstallNativeHandOverride()` подменяет только `handgrasp*`; `HandRectAtPivot()` пересчитывает draw centre вокруг grip, не меняя логический native hitbox отдельно. При отсутствии материала остаётся родная C:U рука |
| Немного отдалить мини-игры без рассинхронизации hitbox | `zc_woundsystem_compat_minigame_zoom 0.85` и `zc_woundsystem_compat_native_minigame_zoom 0.85` (migration revision 6). Native non-fullscreen ветка `ApplyFullscreenClip()` одновременно уменьшает `GetRect()` (760→646 при базовой геометрии) и возвращает `Clip.Scale()*0.85`: wound board, рука, `SimToScreen/ScreenToSim` и hitbox получают один масштаб. WSZC продолжают использовать общий `MinigameScale()`; `zoom 1` возвращает прежний размер |
| Шрапнель не успевает перекрыть бинт | `ApplyBandageToOrganism()` сортирует tagged/extraction раны первыми, `bandage_strength 3` даёт одному полному кругу GAUZE budget `11.25` bleed units (максимальная начальная 5-piece рана = `8`). `CompactWoundTable()` сохраняет нулевые managed-записи, а `org.wszc_shrapnel_closed` / `org.wszc_shrapnel_aftercare_closed` сохраняют закрытое состояние даже после настоящего native `sv_blood.lua:131 table.remove(org.wounds,i)`. Ticks не поднимают их до `0.5`/базовой severity между кругами; новый осколок, новое извлечение и unwrap очищают соответствующий marker. Extraction tag — строка `WSZC_SHRAPNEL_EXTRACTION`. `ShrapnelBandageInProgress()` останавливает только новый lodged severity/pain growth на время активной перевязки выбранной конечности, включая работу другого медика. `ShrapnelAftercarePending()` пропускает обязательный финальный input при normal bleed 0, но artery-only fast path по-прежнему не тратит предмет. Проверены настоящие `WSZC_BandageInput`, treatment budget `100/12` и native ZCity-списание по фактической severity для ёмкостей 40/150, lodged/aftercare/infection ticks; unwrap→extract→re-bandage не удалён |
| Стабилизировать руку/курсор | `WSZC.StabilizeHandPhysics()` обнуляет только pain-shake, сохраняя native maxLength; `WSZC.HandCursorScale()` = `0.55` задаёт компактный размер в WSZC и native override; `WSZC.MinigameActive()` знает все нативные мини-игры C:U. Cursor watchdog использует Sync и не создаёт 20 Гц arrow/blank flicker. |
| Респавн после смерти | `WSZC.MinigameContextOK()` возвращает `false` для `not LocalPlayer():Alive()`; `WSZC.MinigameActive()` / `WSZCMinigameActive()` / `NativeMinigameActive()` всё проверяют. `WSZC.ClearAllMinigameState()` на `PlayerDeath`/`PlayerSpawn` сбрасывает `MinigameHUDOpen`, `MinigameFrozenAngles`, `_ViewModelHidden` и `MG.active` у всех 7 таблиц мини-игр. Серверный `WSZC_MinigameServerLock` выходит сразу для мёртвого игрока, чтобы `PlayerDeathThink` получил свободный `CUserCmd`. |

Валидация: все 11 Lua-файлов проходят `luaparser`, `addon.json` — JSON-парсер.
Актуальный полный suite: `tools/tests/test_wszc_regression.py` — **106/106**,
`tools/tests/test_gameplay_regression.py` — **84/84**,
`tools/tests/test_bandage_regression.py` — **33/33** (включая real client circle → captured native net packets → server treatment/`completed` close); всего **223/223**.
Новые проверки покрывают 16-ю часть, native first-life insertion без дублей,
head+neck pixel identity вне шва, Neck hitbox/Skin/Muscle tooltip, Broken neck,
раздельные Head1/Neck1/neckartery и skull-treatment, а также SHA-256 исходных ZIP.
Runtime-проверки на lupa покрывают общий compact scale и точный rotated pivot
руки на `0/37/90/290°`, настоящий WSZC Think с курсором в центре (без spring и
collision-сдвига), игнорирование `100/400`, native zoom `GetRect()+Clip.Scale()`,
два pin-режима, ZCity-расход `severity 4 = 4` для ёмкостей 40/150, near-empty cap,
бесплатный zero-severity aftercare и отсутствие второго native onProgress,
два watchdog refresh без arrow-flicker, HUD/фильтры,
ампутации/ragdoll/`brokenribs`, артерии/жгуты, нулевое внешнее кровотечение под
бинтом, стадии инфекции 240/420/600 с, однократный native-style `ply:Kill()`,
reverse unwrap (180° не снимает, 360° снимает без item cost), growing
extraction bleed/pain, timed partial GAUZE с настоящим server input и отсутствием
respawn нулевой раны после native table.remove, новое попадание после clot, обязательную финальную повязку при zero bleed. ZIP / mirror /
`MANIFEST.txt` и 651 материал проверяются сборочным тестом.
Живой GMod-сервер ассистентом не запускался; автоматические проверки не заменяют
live-проверку баланса и ввода.

## По live-скриншотам №6 (`Screenshot_2-8`, `Screenshot_3-5`)

### По live-скриншотам №6: пять исправлений (`Screenshot_2-8`, `Screenshot_3-5`)

| Претензия | Что было не так | Исправление |
| --- | --- | --- |
| «рукой двигать не могу в бандаже» | `InputMouseApply` и `SetupMove` вызывали `cmd:SetMouseX(0)` / `SetMouseY(0)`. При `gui.EnableScreenClicker(true)` GMod питает `gui.MousePos()` из того же `CUserCmd` mouse delta — обнуление прибивало курсор к `(0,0)`, и `HandPhysics.Step()` видел нулевую цель. | Оба сеттера удалены. Заморозка камеры (`SetViewAngles`), нулевое движение/кнопки и `return nil` сохранены. Мышь доходит и до VGUI-курсора, и до мини-игры. |
| «я осколок рожаю или че, где нижняя часть откуда он достается?» | `minigameshrapnel.png` ошибочно сочли чёрной панелью и подавляли в `surface.DrawTexturedRect`; это **передний слой раны** (`cl_shrapnel.lua:421`, `cl_syringe.lua:540`). Плюс `fullscreen_native 1` умножал `Clip.Scale()` на `NativeFullscreenK()` до 2.2×, растягивая осколок 26×138 в огромный обрезанный спрайт и уводя низ раны за экран. | Подавление удалено полностью; добавлены `WSZC.IsMinigameWoundLayer()` и белый список `WSZC.IsMinigameGameplaySprite()` (рана, осколок, рука, пинцет, `bandageOuter`, `Icons.*`) в HUD-фильтре. `fullscreen_native` по умолчанию `0`, `native_minigame_zoom` `0.85` → квадрат 646 px; `1` → прежние 760 px. `text=all` убирает только заголовки/инструкции/чёрный chrome. |
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
