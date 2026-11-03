# ZCity ↔ Casualties: Unknown compatibility

Отдельный GMod-аддон, который включает мост `lua/homigrad/woundbridge` из `zcity.zip`
с приложенной версией **Casualties: Unknown Health System Beta** (`casualites unknown.zip`).

Архивы исходных аддонов не изменяются. Все патчи делаются в рантайме, после загрузки C:U и ZCity.

## Зачем он нужен

В `zcity.zip` уже есть мост, но он рассчитан на более новую версию C:U API:
`WoundSystem.Health.HandleDamage`, `ApplyItemToBody`, `StartExternalMinigame`,
`ProcessImpactDamage`, `RagdollBoneNameToLimb`, `Fn`, `Const`, `SendCardioUpdate`,
`ResetPlayer` и т.д. В приложенном C:U эти функции либо локальные, либо отсутствуют,
поэтому серверный `WB.IsEnabled()` возвращает `false`, а ZCity продолжает работать
через legacy `ply.organism`.

Этот аддон:

1. Патчит `WB.IsEnabled()` на сервере и клиенте; решение синхронизируется через
   `SetGlobalBool("WSZC_Ready", true)`, поэтому HUD и сервер не расходятся.
2. Экспортирует недостающие C:U-функции в `WoundSystem.Health`.
3. Подменяет нативный хук `EntityTakeDamage / WoundSystem_Damage` обёрткой:
   при включённом мосте он **не** обрабатывает исходный ZCity-хит повторно,
   а при `zc_woundsystem_bridge 0` снова работает как обычный C:U.
4. Заставляет C:U использовать сегмент, уже вычисленный ZCity
   (`ply._WoundBridgeLimb` из кости/hitgroup), через proxy `Const.HitgroupToLimb`
   и `Fn.PickRandomDamageLimb` в upvalue нативного хука.
5. Пропускает медицину ZCity через определения предметов C:U
   (`WoundSystem.Items.*`, bandage/syringe profiles, `WoundSystem.UseMedicalItem`).
6. **Открывает настоящие bandage/syringe мини-игры C:U, но только для тех
   ZCity-предметов, у которых есть `spec.mg`** — то есть для предметов, которые
   по логике ZCity не должны применяться мгновенно. Мгновенные предметы
   остаются мгновенными.
7. Не даёт C:U создать второй ragdoll: перехватывает его внутренний
   `ents.Create("prop_ragdoll")`, создаёт ZCity `hg.Fake`, зеркалит
   `body.unconsciousRagdoll` и защищает ZCity-ragdoll от удаления при wake.
8. Оставляет `ply.organism` теневой проекцией: броня/пенетрация, hitgroup/кость,
   ragdoll/fake, blood FX, силы и регистрация попадания остаются за ZCity;
   раны/лечение/физиология — за C:U.

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

В консоли при успехе будет:

```text
[ZCity/CU compat] compatibility layer active (C:U owns wounds, ZCity owns hits)
```

## Мини-игры: где они включаются

ZCity сам решает, что предмет не мгновенный: в `WB.SwepSpecs` и
`WB.MedkitModes` у таких спецов стоит поле `mg`, и только тогда
`WB.StartMinigame()` вызывает `WoundSystem.Health.StartExternalMinigame()`.
Наш адаптер дополнительно проверяет `spec.mg` через upvalue bridge-замыканий,
поэтому даже прямой вызов API не откроет мини-игру для мгновенного предмета.

| ZCity-предмет / режим | Мини-игра | Что происходит |
| --- | --- | --- |
| `weapon_bandage_sh`, `weapon_bigbandage_sh` | bandage (`GAUZE` / `STERILIZEDBANDAGE`) | эффект и расход ZCity-предмета идут по мере намотки |
| `weapon_medkit_sh`, режим `1` | bandage (`GAUZE`) | то же |
| `weapon_morphine`, `weapon_fentanyl`, `weapon_naloxone` | syringe | доза и расход идут по мере нажатия поршня |
| `weapon_medkit_sh`, режим `2` | syringe (`MORPHINE`, oneshot) | мини-игра, доза применяется порциями |
| `weapon_needle`, `weapon_medkit_sh`, режим `5` | syringe (`SALINE` → `INJECTION`) | не делится: применяется при закрытии, chest drain требует ≥90% введения |
| `weapon_medkit_sh`, режим `3` | syringe (`SALINE` → `BLOODCOAGULANT`) | применяется при закрытии, доза масштабируется `session.deferredUsed / startAmount` |
| `weapon_adrenaline`, `weapon_betablock`, `weapon_mannitol`, `weapon_thiamine` | syringe (`SALINE`, body-эффект) | body-эффект масштабируется введённой дозой |
| `weapon_tourniquet`, `weapon_painkillers`, `weapon_medkit_sh` режим `4`, blood bag и прочие спецы без `mg` | **нет** | старая мгновенная ветка `WB.SwepHeal`, без открытия UI |

Для «живых» предметов (`live`) `onProgress` вызывается на каждом wrap / толчке
поршня: C:U применяет часть эффекта к **цели**, а ZCity списывает часть своего
SWEP. Для неделимых предметов работа копится в `session.deferredUsed`, а
`onClose` применяет масштабированную дозу. Смерть, респавн, отключение моста,
сломанная игла, потеря цели/сегмента и замена сессии считаются прерыванием —
ничего не применяется и не списывается.

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
- AED / shrapnel / dislocation мини-игры не используются: у ZCity для них нет
  `spec.mg`, они остаются доступны только через родной C:U инвентарь.

## Конвары

| Конвар | Откуда | Назначение |
| --- | --- | --- |
| `zc_woundsystem_bridge` | ZCity | `1` — мост включён; `0` — полностью legacy `organism`, наш `EntityTakeDamage`-guard пропускает нативный C:U хук. |
| `zc_wound_damage_scale` | ZCity | Множитель урона, передаваемого в C:U. |
| `zcity_wounds_collision_scale` | ZCity | Множитель collision/impact force. |
| `zc_woundsystem_minigames` | ZCity | `1` — ZCity вызывает external-minigame API для не-мгновенных предметов; `0` — все предметы снова применяются мгновенно, активные сессии закрываются. |
| `zc_woundsystem_compat_minigames` | этот аддон | `1` — наша реализация мини-игр активна; `0` — `StartExternalMinigame` возвращает `false`, т.е. прежнее instant-поведение без правки ZIP. |
| `zc_woundsystem_compat_debug` | этот аддон | `1` — диагностика найденных C:U upvalue и открытия/закрытия сессий. |
| `woundsys_enabled` | C:U | Если `0`, `WB.IsEnabled()` снова `false`. |

## Ограничения

- Мини-игры открываются **только** для ZCity-спецов с `spec.mg`; мгновенные
  предметы намеренно не переведены в мини-игры.
- C:U-инвентарь не интегрируется с ZCity SWEP'ами: мост лечит цель напрямую,
  используя виртуальный слот и namespaced-протокол. Родной инвентарь C:U
  продолжает работать как раньше.
- Рагдолл/камера/визуальные эффекты unconscious остаются на стороне ZCity
  (`hg.Fake` / `hg.FakeUp`). C:U не помечает ZCity-ragdoll как свой NW-прокси,
  чтобы не было двойного `EntityTakeDamage` по ragdoll.
- Аддон использует `debug.getupvalue/setupvalue/getlocal` и точечный перехват
  `ents.Create`. Это безопасно для приложенной версии C:U, но после крупного
  обновления C:U может потребовать адаптации. Если будущая версия C:U уже
  экспортирует `HandleDamage` + `ApplyItemToBody`, аддон отключает только
  патчи урона, но всё равно подменяет external-minigame API; при необходимости
  это отключается `zc_woundsystem_compat_minigames 0`.
- Хуки сторонних аддонов (`PreHomigradDamage`, `HomigradDamage`,
  `PostEntityTakeDamage`, `simple eye gore`, `zcitygore`, `project hemogen blood`)
  не переопределяются.
- Проверено синтаксически (`luaparser`) и на заглушечном Lua-рантайме;
  на живом GMod-сервере не прогонялось.

## Файлы

```text
woundsystem_zcity_compat/
├── addon.json
├── README.md
└── lua/autorun/
    ├── sh_zcity_woundsystem_compat.lua        # общий патч WB.IsEnabled + WSZC_Ready
    ├── client/
    │   ├── cl_zcity_woundsystem_compat_minigames.lua  # виртуальный слот, WSZC_* приём, загрузка копий
    │   ├── wszc_cl_bandage.lua               # namespaced-копия C:U bandage UI
    │   └── wszc_cl_syringe.lua               # namespaced-копия C:U syringe UI
    └── server/
        ├── sv_zcity_woundsystem_compat.lua           # экспорты, guard, урон, лечение, ragdoll
        └── sv_zcity_woundsystem_compat_minigames.lua # external API, сессии, прогресс, закрытие
```

## Диагностика

Если строка «compatibility layer active» не появилась:

1. `zc_woundsystem_bridge 1`
2. `woundsys_enabled 1`
3. `zc_woundsystem_compat_debug 1` и перезапустить карту
4. Проверить, что в `lua/autorun` загрузились и `sh_health_init.lua` C:U,
   и `loader.lua` ZCity.

Если мини-игра не открывается:

1. `zc_woundsystem_minigames 1`
2. `zc_woundsystem_compat_minigames 1`
3. Убедиться, что клиент докачал `cl_zcity_woundsystem_compat_minigames.lua`,
   `wszc_cl_bandage.lua`, `wszc_cl_syringe.lua` (в консоли не должно быть
   `minigame client load failed`).
4. `zc_woundsystem_compat_debug 1` — в логах будут строки `opened bandage/syringe session`.

Сообщение `Could not intercept C:U unconscious ragdoll creation` означает, что
не удалось найти внутреннюю функцию C:U через `debug`: урон и лечение при этом
работают, но возможен дублирующийся ragdoll.
