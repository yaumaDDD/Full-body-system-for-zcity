# ZCity ↔ Casualties: Unknown compatibility

Отдельный GMod-аддон, который соединяет стандартную систему здоровья ZCity
(`ply.organism`) с **Casualties: Unknown Health System Beta**
(`casualites unknown.zip`), не изменяя исходные ZIP-архивы. Все патчи делаются в
рантайме, после загрузки C:U и ZCity.

## Режим по умолчанию: `ply.organism` авторитетен

По решению владельца проекта здоровьем управляет **стандартная ZCity**:
`ply.organism`, Organs+, боль/шок/кровотечение, hitgroup/броня/пенетрация,
ragdoll/fake и death logic остаются за ZCity. C:U остаётся загруженной, но
выступает только как:

- **UI** — панель осмотра травм `WoundSystem.OpenHealthHUD()` (self-only);
- **мини-игры** — bandage/syringe для «живых» ZCity-предметов и родная игра
  извлечения осколков;
- **показатели** — `BodyState`/`PlayerLimbs` в C:U синхронизируются как
  *теневая проекция* ZCity-организма (никогда наоборот);
- **протокол шрапнели** — единое целочисленное поле `state.shrapnel`.

Переключатель: `zc_woundsystem_compat_authority 1` (по умолчанию).
`zc_woundsystem_compat_authority 0` возвращает прежний мост, где C:U полностью
владела ранами («C:U owns wounds, ZCity owns hits»).

> `woundsys_enabled` **не выключается** ни в одном режиме: он гатит HUD C:U,
> серверные обработчики мини-игр и `WoundSystem_ShrapnelStart`.

## Зачем аддон нужен

В `zcity.zip` уже есть мост `lua/homigrad/woundbridge`, но он рассчитан на более
новую версию C:U API: `WoundSystem.Health.HandleDamage`, `ApplyItemToBody`,
`StartExternalMinigame`, `ProcessImpactDamage`, `RagdollBoneNameToLimb`, `Fn`,
`Const`, `SendCardioUpdate`, `ResetPlayer` и т.д. В приложенном C:U эти функции
либо локальные, либо отсутствуют, поэтому `WB.IsEnabled()` без патча возвращает
`false`.

Аддон:

1. Патчит `WB.IsEnabled()` на сервере; решение синхронизируется через
   `SetGlobalBool("WSZC_Ready", true)` и `WSZC_OrganismAuthority`.
   На клиенте в authority-режиме мост намеренно сообщает `false`, чтобы
   родные HUD/виньетки/эффекты/инерция ZCity остались стандартными; панель C:U
   открывается по кнопке.
2. Экспортирует недостающие C:U-функции в `WoundSystem.Health`.
3. Подменяет нативный хук `EntityTakeDamage / WoundSystem_Damage` обёрткой.
   В authority-режиме C:U **не моделирует урон вовсе**: её обработчик заканчивался
   `dmginfo:SetDamage(0)`, что обнулило бы ZCity-хит. Вместо этого хит целиком
   обрабатывает `homigrad-damage`, а наш `PostEntityTakeDamage` снимает сырой
   урон для правил шрапнели.
4. Оборачивает `Org Think "Main"`, `homigrad-damage`, `Ragdoll Collide "organism"`
   и `hg.velocityDamage` в кратковременный «vanilla context», где
   `WB.IsBridged()` возвращает `false`. Это заставляет исполняться родные ветки
   ZCity (включая все модули Organs+), минуя `WB.Think`/`WB.ApplyDamage`.
   Медицина и мини-игры работают **вне** этого контекста и поэтому видят мост
   включённым.
5. Заглушает `WB.ApplyDamage/ApplyCollision/ApplyFall/AddWoundManual/Amputate` и
   заменяет `WB.Sync/Think` на однонаправленную синхронизацию
   `ply.organism → C:U` (4 Гц, только изменённые лимбы). Поля `shrapnel`,
   `isBandaged`, `hasInjection`, `customStatuses` C:U владеет сама — тень их не
   трогает.
6. Отключает вторую физиологию C:U (таймеры `WoundSystem_LimbTick`,
   `WoundSystem_CardioTick`, `*_Start`, HEV AutoMedic, self-harm Think и
   сопутствующие damage-хуки), но **оставляет** `WoundSystem_ShrapnelTick` —
   он нужен родной мини-игре. Повторно подавляет их каждые 5 с на случай
   `RebuildWoundTimers()` после смены конваров.
7. Зеркалит медицинские эффекты: снимок C:U-состояния до `WB.SwepHeal` /
   `ApplyItemToBody` и перенос полученной дельты обратно в `ply.organism`
   (`blood`, `pain`, `pulse`, `shock`, `brain`, `bleed`, `painkiller`,
   `adrenaline`, повреждение лимба). One-dose предметы остаются мгновенными.
8. Не даёт C:U создать второй ragdoll: перехватывает её внутренний
   `ents.Create("prop_ragdoll")`, создаёт ZCity `hg.Fake`, зеркалит
   `body.unconsciousRagdoll` и защищает ZCity-ragdoll от удаления при wake.
9. Добавляет в круговой селектор ZCity кнопку «Проверить травмы», которая
   открывает готовую панель осмотра C:U, а не новый самописный интерфейс.
10. Синхронизирует `org.otrub` в `WoundSystemUnconscious`, иначе гейт
    `OpenHealthHUD()` мог навсегда заблокироваться после выключения физиологии C:U,
    и сбрасывает шрапнель при респавне (в том числе после `LoadPlayerPersistData`
    при переходе между картами).

## Шрапнель: одно состояние, три источника

Поле `state.shrapnel` в `PlayerLimbs` — **единственный** источник истины.
Поля `source` нет, второй мини-игры нет: gunshot, blast и glass пишут один и тот
же счётчик, и родная кнопка `REMOVE SHRAPNEL` в панели C:U всегда открывает
один и тот же `BuildShrapnelSession()`.

| Источник | Правило | Откуда перенесено |
| --- | --- | --- |
| Пуля / дробь | +1 за попадание, блокируется HEV-шансом, лимит `ShrapnelPieceCount` (5) | `Fn.AddGunshotShrapnel` из обработчика урона C:U (в authority-режиме он больше не вызывается) |
| Взрыв | на некритичных лимбах: `raw≥20` 60 %, `raw≥40` 50 %, `raw≥70` 40 %, до 3 осколков | ветка `DMG_BLAST` в `WoundSystem_Damage` |
| Стекло | +1 за удар рукой/ногой по стеклу (стоячий игрок, brush `func_breakable_surf`, ragdoll-коллизии) | отсутствовало: в ZCity хук `sv_input.lua:441-446` закомментирован, `WB.SurfaceCut` пишет только skin/bleed |

Сырой урон снимается **до** `dmginfo:ScaleDamage(0.15)` внутри обёртки
`homigrad-damage`, иначе пороги взрыва никогда не сработали бы. Поверхности
берутся из `data["TheirSurfaceProps"]` через `util.GetSurfacePropName`, как в
`hg.velocityDamage` (ZCity `bleedSurfaces`). Лимит берётся из настоящего
`WoundSystem.Health.Constants.ShrapnelPieceCount` (не из внутреннего `Const`).

`org.wszc_shrapnel` — теневая копия для ZCity-кода. Пока осколок не извлечён,
`org.wszc_shrapnel_floor` удерживает повреждение лимба от регенерации; после
извлечения C:U пишет `state.shrapnel = remaining`, тень подтягивает новое
значение и блок снимается.

Вход в мини-игру — кнопка «Проверить травмы» → родная панель C:U → точка
`REMOVE SHRAPNEL`. Инструмент не требуется: `slotIdx = 0`, `hasTweezers = false`,
игра идёт «руками» (ветка `not MG.hasTweezers`), `ConsumeToolDurability` не
вызывается. Инвентарь C:U не интегрируется с ZCity SWEP'ами.

## Установка

1. Скопировать папку `woundsystem_zcity_compat` в `garrysmod/addons/`.
2. Убедиться, что установлены/подключены оригинальные аддоны из репозитория:
   - `casualites unknown.zip` → `casualties_unknown_health_system_beta`
   - `zcity.zip` → `z_city`
   - `zcity organs +.zip` → `z_city_organs_plus`
   - `project hemogen blood.zip` → `project_hemogen_zcity`
   - `simple eye gore.zip` → `simple_eye_gore`
   - `zcitygore.zip` → `zсity_gore_v2`
3. Перезапустить сервер/карту. Порядок загрузки не критичен: аддон повторяет
   инициализацию через `timer.Simple`, `InitPostEntity` и `HomigradRun`, пока не
   увидит и C:U, и `hg.WoundBridge`. Клиентские мини-игры подключаются отдельно,
   после загрузки C:U `cl_clip.lua` / `cl_health_gui.lua` / `WoundSystem.Items`.

В консоли при успехе будет одна из строк:

```text
[ZCity/CU compat] compatibility layer active (ply.organism owns health; C:U = HUD, minigames, shrapnel)
[ZCity/CU compat] organism-authoritative mode active (ply.organism owns health; C:U = HUD, minigames, shrapnel)
```

При `zc_woundsystem_compat_authority 0`:

```text
[ZCity/CU compat] compatibility layer active (C:U owns wounds, ZCity owns hits)
```

## Мини-игры: где они включаются

ZCity вызывает `WoundSystem.Health.StartExternalMinigame()` только для спецов с
`spec.mg`. По уточнению владельца проекта мини-игру получают **не все** такие
спецы, а только бинты и непрерывные шприцевые препараты. One-dose предметы
(`spec.oneshot`, `mg.vehicle`, `kind=apply/body`) остаются мгновенными: адаптер
возвращает `false`, и `WB.StartMinigame()` уходит в старую instant-ветку
`WB.SwepHeal`. Дополнительно проверяется `spec.mg` через upvalue замыканий,
поэтому предметы без `mg` тоже не открывают UI.

| ZCity-предмет / режим | Поведение |
| --- | --- |
| `weapon_bandage_sh`, `weapon_bigbandage_sh`, `weapon_medkit_sh` режим `1` | **bandage мини-игра**: эффект и расход ZCity-предмета идут по мере намотки |
| `weapon_morphine`, `weapon_fentanyl` | **syringe мини-игра**: доза и расход идут по мере нажатия поршня |
| `weapon_naloxone` | **мгновенно**, хотя в ZCity есть `spec.mg` (oneshot) |
| `weapon_needle`, `weapon_medkit_sh` режим `5` | **мгновенно** (`INJECTION` / SALINE, apply) |
| `weapon_medkit_sh` режим `2` | **мгновенно** (MORPHINE oneshot) |
| `weapon_medkit_sh` режим `3` | **мгновенно** (BLOODCOAGULANT / SALINE vehicle) |
| `weapon_adrenaline`, `weapon_betablock`, `weapon_mannitol`, `weapon_thiamine` | **мгновенно** (body-эффект / SALINE vehicle) |
| `weapon_tourniquet`, `weapon_painkillers`, `weapon_medkit_sh` режим `4`, blood bag и прочие спецы без `mg` | **мгновенно** (старая ветка `WB.SwepHeal`) |

Для «живых» предметов (`live`) `onProgress` вызывается на каждом wrap / толчке
поршня: C:U применяет часть эффекта к **цели**, а ZCity списывает часть своего
SWEP. В authority-режиме каждая такая доза дополнительно зеркалится в
`ply.organism`. Поддержка `session.deferredUsed` и масштабированной дозы в
`onClose` оставлена для совместимости с контрактом `WB.StartMinigame()`. Смерть,
респавн, отключение моста, сломанная игла, потеря цели/сегмента и замена сессии
считаются прерыванием — ничего не применяется и не списывается.

### Как это реализовано без правки C:U

- В `lua/autorun/client/` лежат namespaced-копии `cl_bandage.lua` и
  `cl_syringe.lua`. Они рисуют родной C:U UI, но общаются по своим `WSZC_*`
  сообщениям, поэтому не конфликтуют с родным инвентарём C:U.
- Сервер создаёт виртуальный инструмент в слоте `6` (родной инвентарь C:U — слоты `1..5`)
  через `WSZC_MinigameOpen` / `WSZC_MinigameSlot`, открывает сессию через
  `WSZC_BandageOpen` / `WSZC_SyringeOpen`, принимает ввод через
  `WSZC_BandageInput` / `WSZC_SyringeInput`, шлёт `WSZC_MinigameAck` и
  `WSZC_SyringeState`, закрывает через `WSZC_BandageClose` / `WSZC_SyringeClose`
  и `WSZC_MinigameClose`.
- `session.startAmount`, `session.deferredUsed`, `onProgress`, `onClose` и
  причины закрытия (`dead`, `respawn`, `disabled`, `needle_break`,
  `invalid_limb`, `replaced`, `target_gone`, `empty`, `user_cancel`) совпадают
  с контрактом `WB.StartMinigame()`.
- Родные C:U сессии bandage/syringe тоже учитываются в `HasExternalMinigame`
  и закрываются при `StopExternalMinigame`, чтобы две мини-игры не открылись
  поверх друг друга.
- AED / dislocation мини-игры не используются: у ZCity для них нет `spec.mg`.
  Shrapnel-мини-игра, наоборот, **родная C:U** и открывается из панели осмотра.

## Кнопка проверки травм в круговом селекторе

В `zcity.zip` уже есть хук `ZCity_WoundBridge_Inspect`, добавляющий пункт
`Examine Body` → `WB.OpenWoundView()`. Аддон **не рисует свой UI**: он
перехватывает `WB.OpenWoundView`, переименовывает и переподчиняет этот пункт на
«Проверить травмы» и вызывает `WoundSystem.OpenHealthHUD()` из C:U. Если штатный
хук отсутствует (в authority-режиме клиентский `WB.IsEnabled()` равен `false`,
поэтому ZCity может его не добавить), пункт добавляется нашим хуком
`ZCity_WoundBridge_Inspect_WSZC`; его идентификатор сортируется после штатного в
`SortedPairs()`, поэтому двух кнопок не бывает.

- Открывается именно родная панель здоровья/ран C:U, со своим HUD, инвентарём и
  мини-играми. Второго меню, HUD и инвентаря не создаётся.
- Кнопка видна только живому `LocalPlayer()` при готовом аддоне: `WSZC_Ready`,
  `zc_woundsystem_bridge 1`, `woundsys_enabled 1`,
  `zc_woundsystem_compat_inspect_button 1`. Гейт на `WB.IsEnabled()` убран
  намеренно — в authority-режиме он `false` на клиенте. Панель C:U рассчитана на
  `LocalPlayer()`, поэтому кнопка проверяет **себя**; осмотр другого игрока
  через неё невозможен.
- Перед открытием выдерживается `0.12 c`, чтобы круговое меню ZCity успело
  закрыться и не перехватить курсор.
- Команда `wszc_open_wounds` открывает ту же панель (для биндов и диагностики).
- `zc_woundsystem_compat_inspect_button 0` убирает и наш пункт, и штатный
  `Examine Body`.
- При закрытии мини-игры курсор не снимается, если панель C:U ещё открыта
  (`WoundSystemHealthHUDOpen`).

## Конвары

| Конвар | Откуда | Назначение |
| --- | --- | --- |
| `zc_woundsystem_compat_authority` | этот аддон, replicated | **По умолчанию `1`**: `ply.organism` авторитетен, C:U = UI/мини-игры/показатели/шрапнель. `0` — прежний мост, C:U владеет ранами. Переключается на ходу, карту перезапускать не обязательно. |
| `zc_woundsystem_compat_shrapnel` | этот аддон | `1` — единый `state.shrapnel` (пули, взрывы, стекло); `0` — не создавать осколки. |
| `zc_woundsystem_compat_glass_shrapnel` | этот аддон | `1` — осколки от стекла руками/ногами и ragdoll-коллизий. |
| `zc_woundsystem_compat_shrapnel_regen_block` | этот аддон | `1` — застрявший осколок блокирует регенерацию лимба ZCity до извлечения. |
| `zc_woundsystem_compat_shadow` | этот аддон | `1` — зеркалить травмы ZCity в HUD C:U (`BodyState`/`PlayerLimbs`). |
| `zc_woundsystem_compat_organism_debug` | этот аддон | `1` — диагностика обёрток, шрапнели и медицинских дельт. |
| `zc_woundsystem_bridge` | ZCity | `1` — мост включён; `0` — полностью legacy `organism`. |
| `zc_wound_damage_scale` | ZCity | Множитель урона, передаваемого в C:U (только режим `authority 0`). |
| `zcity_wounds_collision_scale` | ZCity | Множитель collision/impact force (только режим `authority 0`). |
| `zc_woundsystem_minigames` | ZCity | `1` — ZCity вызывает external-minigame API для спецов с `spec.mg`; адаптер всё равно оставляет one-dose предметы мгновенными. |
| `zc_woundsystem_compat_minigames` | этот аддон | `1` — наша реализация мини-игр активна; `0` — instant-поведение без правки ZIP. |
| `zc_woundsystem_compat_debug` | этот аддон | `1` — диагностика найденных C:U upvalue и открытия/закрытия сессий. |
| `zc_woundsystem_compat_inspect_button` | этот аддон (client) | `1` — показывать «Проверить травмы»; `0` — скрыть кнопку и штатный `Examine Body`. |
| `woundsys_enabled` | C:U | Должен быть `1` в обоих режимах. `0` отключает HUD, серверные обработчики мини-игр и протокол шрапнели. |

## Ограничения

- Режим `authority 1` не обещает полной 1:1 vanilla-эквивалентности Organs+:
 Organs+ не ссылается на `WoundBridge/WoundSystem`, а `hg.send_organism` шлёт
 фиксированный набор полей. Локальные счётчики, эффекты глаз, debug и кнопка
 работают; часть «берсерк/стимуляция» завязана на поля, которые в bridged
 `Org Think "Main"` не обновлялись и в vanilla-ветке тоже могут не
 обновляться. Чистый vanilla без C:U достигается `zc_woundsystem_bridge 0`
 + `woundsys_enabled 0`, но тогда исчезают панель и мини-игры.
- C:U-инвентарь не интегрируется с ZCity SWEP'ами: мини-игры лечения используют
 виртуальный слот и namespaced-протокол, а извлечение осколков идёт «руками».
- Кнопка «Проверить травмы» открывает панель C:U только для себя: приложенная
 версия C:U не имеет UI осмотра другого игрока.
- Показатели в панели C:U — теневая проекция (4 Гц), а не самостоятельная симуляция.
 Они могут отставать на доли секунды от `ply.organism`; авторитетом остаётся
 ZCity.
- Рагдолл/камера/визуальные эффекты unconscious остаются на стороне ZCity
 (`hg.Fake` / `hg.FakeUp`).
- Аддон использует `debug.getupvalue/setupvalue/getlocal`, точечный перехват
 `ents.Create` и обёртки хуков. Это безопасно для приложенной версии C:U, но после
 крупного обновления C:U может потребовать адаптации.
- Хуки сторонних аддонов (`PreHomigradDamage`, `HomigradDamage`,
 `PostEntityTakeDamage`, `simple eye gore`, `zcitygore`, `project hemogen blood`)
 не переопределяются.
- Проверено синтаксически (`luaparser`) и на заглушечном Lua-рантайме
 (authority-режим, inspect, мини-игры); на живом GMod-сервере не прогонялось.

## Файлы

```text
woundsystem_zcity_compat/
├── addon.json
├── README.md
└── lua/autorun/
    ├── sh_zcity_woundsystem_compat.lua        # общий патч, authority, vanilla context, WSZC_Ready
    ├── client/
    │   ├── cl_zcity_woundsystem_compat_minigames.lua  # виртуальный слот, WSZC_* приём, загрузка копий
    │   ├── cl_zcity_woundsystem_compat_inspect.lua    # «Проверить травмы» → WoundSystem.OpenHealthHUD()
    │   ├── wszc_cl_bandage.lua               # namespaced-копия C:U bandage UI
    │   └── wszc_cl_syringe.lua               # namespaced-копия C:U syringe UI
    └── server/
        ├── sv_zcity_woundsystem_compat.lua           # экспорты, guard урона, лечение, ragdoll
        ├── sv_zcity_woundsystem_compat_minigames.lua # external API, сессии, прогресс, закрытие
        └── sv_zcity_woundsystem_compat_organism.lua  # authority-режим: шрапнель, тень, vanilla-обёртки
```

## Диагностика

Если строка «compatibility layer active» не появилась:

1. `zc_woundsystem_bridge 1`, `woundsys_enabled 1`
2. `zc_woundsystem_compat_debug 1` и перезапустить карту
3. Проверить, что в `lua/autorun` загрузились и `sh_health_init.lua` C:U,
   и `loader.lua` ZCity.

Если мини-игра не открывается:

1. `zc_woundsystem_minigames 1`, `zc_woundsystem_compat_minigames 1`
2. Убедиться, что клиент докачал `cl_zcity_woundsystem_compat_minigames.lua`,
   `wszc_cl_bandage.lua`, `wszc_cl_syringe.lua`.
3. `zc_woundsystem_compat_debug 1` — в логах будут строки `opened bandage/syringe session`
   или `instant fallback ... (one-dose ZCity item)`.
4. Помнить, что `weapon_naloxone`, `weapon_needle`, body-препараты и медкит
   режимы `2/3/5` намеренно не открывают мини-игру.

Если осколки не появляются:

1. `zc_woundsystem_compat_shrapnel 1`, `zc_woundsystem_compat_glass_shrapnel 1`
2. `zc_woundsystem_compat_organism_debug 1` — строки `shrapnel +N on <limb>`.
3. Для взрыва важен сырой урон до `ScaleDamage(0.15)`; он снимается обёрткой
   `homigrad-damage`. Если сторонний аддон заменил этот хук после нас, нужна
   адаптация имени хука.
4. Кнопка `REMOVE SHRAPNEL` появляется в панели C:U только при
   `state.shrapnel > 0`; проверьте `zc_woundsystem_compat_shadow 1`.

Если в круговом меню нет «Проверить травмы»:

1. `zc_woundsystem_bridge 1`, `woundsys_enabled 1`,
   `zc_woundsystem_compat_inspect_button 1`.
2. Убедиться, что в консоли есть `compatibility layer active` — клиент ждёт
   серверный `WSZC_Ready`.
3. Команда `wszc_open_wounds` должна открыть ту же панель C:U; если она не
   работает, значит не загрузился `cl_health_gui.lua` C:U.

Сообщение `Could not intercept C:U unconscious ragdoll creation` означает, что
не удалось найти внутреннюю функцию C:U через `debug`: урон и лечение при этом
работают, но возможен дублирующийся ragdoll.
