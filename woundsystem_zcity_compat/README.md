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
5. Пропускает медицину ZCity (`weapon_bandage_sh`, `weapon_morphine`,
   `weapon_medkit_sh`, blood bag и др.) через определения предметов C:U
   (`WoundSystem.Items.*`, bandage/syringe profiles, `WoundSystem.UseMedicalItem`).
6. Не даёт C:U создать второй ragdoll: перехватывает его внутренний
   `ents.Create("prop_ragdoll")`, создаёт ZCity `hg.Fake`, зеркалит
   `body.unconsciousRagdoll` и защищает ZCity-ragdoll от удаления при wake.
7. Оставляет `ply.organism` теневой проекцией: броня/пенетрация, hitgroup/кость,
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
   увидит и C:U, и `hg.WoundBridge`.

В консоли при успехе будет:

```text
[ZCity/CU compat] compatibility layer active (C:U owns wounds, ZCity owns hits)
```

## Конвары

| Конвар | Откуда | Назначение |
| --- | --- | --- |
| `zc_woundsystem_bridge` | ZCity | `1` — мост включён; `0` — полностью legacy `organism`, наш `EntityTakeDamage`-guard пропускает нативный C:U хук. |
| `zc_wound_damage_scale` | ZCity | Множитель урона, передаваемого в C:U. |
| `zcity_wounds_collision_scale` | ZCity | Множитель collision/impact force. |
| `zc_woundsystem_minigames` | ZCity | Оставлен как есть. Наш `StartExternalMinigame` возвращает `false`, поэтому ZCity сам переходит к мгновенному применению лечения. |
| `zc_woundsystem_compat_debug` | этот аддон | `1` — диагностические сообщения о найденных C:U upvalue. |
| `woundsys_enabled` | C:U | Если `0`, `WB.IsEnabled()` снова `false`. |

## Ограничения

- **Мини-игры C:U не открываются.** Лечение применяется сразу по тому же
  принципу, что и instant-ветка `WB.SwepHeal`: эффект масштабируется дозой,
  предмет расходуется ZCity. Клиентские мини-игры bandage/syringe/AED остаются
  доступны только через родной инвентарь C:U.
- C:U-инвентарь не интегрируется с ZCity SWEP'ами: мост лечит цель напрямую,
  используя виртуальный слот `WoundSystem.Items.CreateSlot`.
- Рагдолл/камера/визуальные эффекты unconscious остаются на стороне ZCity
  (`hg.Fake` / `hg.FakeUp`). C:U не помечает ZCity-ragdoll как свой NW-прокси,
  чтобы не было двойного `EntityTakeDamage` по ragdoll.
- Аддон использует `debug.getupvalue/setupvalue/getlocal` и точечный перехват
  `ents.Create`. Это безопасно для приложенной версии C:U, но после крупного
  обновления C:U может потребовать адаптации. Если будущая версия C:U уже
  экспортирует `HandleDamage` + `ApplyItemToBody`, аддон почти полностью
  отключается и не мешает штатному мосту.
- Хуки сторонних аддонов (`PreHomigradDamage`, `HomigradDamage`,
  `PostEntityTakeDamage`, `simple eye gore`, `zcitygore`, `project hemogen blood`)
  не переопределяются.
- Проверено синтаксически и на заглушечном Lua-рантайме; на живом GMod-сервере
  не прогонялось.

## Файлы

```text
woundsystem_zcity_compat/
├── addon.json
├── README.md
└── lua/autorun/
    ├── sh_zcity_woundsystem_compat.lua   # общий патч WB.IsEnabled + WSZC_Ready
    └── server/
        └── sv_zcity_woundsystem_compat.lua  # экспорты, guard, урон, лечение, ragdoll
```

## Диагностика

Если строка «compatibility layer active» не появилась:

1. `zc_woundsystem_bridge 1`
2. `woundsys_enabled 1`
3. `zc_woundsystem_compat_debug 1` и перезапустить карту
4. Проверить, что в `lua/autorun` загрузились и `sh_health_init.lua` C:U,
   и `loader.lua` ZCity.

Сообщение `Could not intercept C:U unconscious ragdoll creation` означает, что
не удалось найти внутреннюю функцию C:U через `debug`: урон и лечение при этом
работают, но возможен дублирующийся ragdoll.
