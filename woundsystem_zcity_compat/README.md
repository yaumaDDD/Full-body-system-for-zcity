# ZCity ↔ Casualties: Unknown compatibility

Отдельный GMod-аддон, который соединяет стандартную систему здоровья ZCity
(`ply.organism`) с **Casualties: Unknown Health System Beta**
(`casualites unknown.zip`), не изменяя исходные ZIP-архивы. Все патчи делаются в
рантайме, после загрузки C:U и ZCity.

В коннектор дополнительно встроены изолированные **71 C:U Lua + 3 ZCity
WoundBridge Lua** (`lua/wszc_vendor/`). Поэтому отдельная установка C:U или
поиск ZCity-версии с WoundBridge больше не обязательны. Внешние
Workshop/GitHub API имеют приоритет; embedded-загрузчик включается только при
их отсутствии и не создаёт второй runtime поверх уже загруженного аддона.

## Адаптивная совместимость со сборками

`WSZC.RefreshCapabilities()` проверяет реальные контракты, а не версию или название
папки. `zc_woundsystem_compat_adaptive 1` включён по умолчанию. Возможны профили:

| Профиль | Условие | Поведение |
|---|---|---|
| `legacy-adapter` | ZCity WoundBridge + узнаваемый legacy damage/medical entrypoint C:U + `debug.getupvalue/setupvalue` | Текущий полный путь; native/external API экспортируются connector-ом |
| `native-api` | C:U экспортирует `HandleDamage`, `ApplyItemToBody`, `GetBody/GetLimbs` | Нативный API сохраняется; при наличии native external minigames WSZC-копии не подменяют его |
| `partial` | Найдены лишь некоторые таблицы/функции | Core не активируется; несовместимые функции остаются выключенными |
| `unavailable` | Внешние API ещё не загружены и embedded fallback ещё не готов/не смог загрузиться | Connector инертен, возможен поздний probe/reprobe; источник виден в строке `runtime:` |

Core не означает автоматическую поддержку всех расширений. Отдельно проверяются:

- `inspection` — C:U `OpenHealthHUD` или `ToggleHealthHUD`;
- `medicine` — native medical API либо ZCity `SwepHeal/GetPlayer`;
- `external_minigames` — native external API либо ZCity `StartMinigame` и оба
  требуемых клиентских C:U minigame source;
- `remote` — inspection плюс native state tables или legacy adapter;
- `organism_extensions` — ZCity `Sync/Think` и `hg.organism.Clear`, чтобы не
  подменять неизвестную симуляцию здоровья.

Ошибка несовместимого Setup записывается в `Compatibility.failures.core` и не
повторяется каждые 0.5 с. Команда `wszc_compat_status` печатает профиль, активный
адаптер, контракты, features и причины отказа. `wszc_compat_reprobe` очищает latch
и повторяет определение после поздней загрузки/смены аддонов.
`zc_woundsystem_compat_prefer_native_api 1` сохраняет native external API;
`adaptive 0` — экспертный legacy override, а не гарантия запуска.

Коннектор **не заменяет саму ZCity** и не обещает поддержать абсолютно любую
её модификацию: `hg.organism`, gamemode и основной ragdoll/damage API должны
существовать. Но C:U/WoundBridge уже являются embedded-зависимостями, а не
отдельным обязательным скачиванием. При изменении смысла `ply.organism`,
damage/ragdoll hooks или анатомии нужен отдельный адаптер по ZIP сборки и
живой двухклиентный тест.

## Режим по умолчанию: `ply.organism` авторитетен

По решению владельца проекта здоровьем управляет **стандартная ZCity**:
`ply.organism`, Organs+, боль/шок/кровотечение, hitgroup/броня/пенетрация,
ragdoll/fake и death logic остаются за ZCity. C:U остаётся загруженной, но
выступает только как:

- **UI** — одна и та же панель `WoundSystem.OpenHealthHUD()` для самоосмотра и лечения выбранного пациента;
- **мини-игры** — bandage/syringe для «живых» ZCity-предметов, родная игра
  извлечения осколков и родная игра **ручного вправления вывихов**
  (`WoundSystemDislocationMinigame`, кнопка `FIX DISLOCATION`);
- **показатели** — `BodyState`/`PlayerLimbs` в C:U синхронизируются как
  *теневая проекция* ZCity-организма (никогда наоборот);
- **протокол шрапнели** — единое целочисленное поле `state.shrapnel`.

Переключатель: `zc_woundsystem_compat_authority 1` (по умолчанию).
`zc_woundsystem_compat_authority 0` возвращает прежний мост, где C:U полностью
владела ранами («C:U owns wounds, ZCity owns hits»).

> `woundsys_enabled` **не выключается** ни в одном режиме: он гатит HUD C:U,
> серверные обработчики мини-игр и `WoundSystem_ShrapnelStart`.

## Лечение другого игрока без отдельного интерфейса

Подойдите к живому игроку на расстояние до 256 units и наведитесь на него или
его ragdoll. Независимая кнопка **«Лечить игрока»** откроет нативный WoundView
с авторитетным snapshot пациента. Обычная «Проверить травмы» остаётся отдельным
самоосмотром и не меняет своё поведение. Remote treatment и его кнопка управляются
`zc_woundsystem_compat_remote_inspect_button 1`, команда для бинда —
`wszc_treat_player`.

Для ragdoll client resolver последовательно проверяет `hg.RagdollOwner`,
`organism.owner`, `ragdoll.ply`, NW `ply/Owner/RagdollOwner` и обратные связи
`FakeRagdoll` / `WoundSystemUnconsciousRagdoll`. Trace берётся из того же
`hg.eyeTrace()`, что у ZCity camera/SWEP; выбранный пациент сохраняется во время
0.25-секундных rebuild открытого radial menu. Client и server измеряют дистанцию
до актуального ragdoll, а не до устаревшей позиции скрытого player entity.

Серверный `PatchBridgePlayerResolver()` сохраняет native `WB.GetPlayer` fast path
и добавляет проверенные owner/current-body/shared-organism links. Поэтому один
resolver работает для всех 12 standalone medical SWEP, всех 5 medkit modes,
bloodbag give/take и continuous minigames, включая proxy ragdoll, который
canonical `hg.RagdollOwner` не смог разрешить.

Remote-модуль **не рисует второй UI и не добавляет patient banner**. Используются
те же 17 native limb id и 17 traced частей custom doll, включая `neck/pelvis`,
материалы, hitboxes, hover, actions и minigames, что у
self-player. Сохраняются и восстанавливаются self `PlayerLimbs`, `Cardio` и
`PlayerStats`; self-updates не затирают открытый snapshot пациента, а после
закрытия сервер присылает свежий self-snapshot.

Пять C:U-слотов остаются скрытыми и при remote treatment: чужой WoundView
визуально и структурно совпадает с самоосмотром без единственного бывшего
inventory-исключения. Расходуемые медицинские предметы применяются штатными
ZCity SWEP непосредственно на player/ragdoll через canonical `WB.SwepHeal`:
предмет и durability расходует **лекарь**, лечение получает **пациент**.

- В WoundView остаются native shrapnel/dislocation и снятие statuses руками.
- Bandage/syringe из ZCity SWEP используют тот же advanced
  `StartExternalMinigame`, где `owner` — медик, `target` — пациент; explicit
  `target/spec/maxDur/live/oneDose` не подменяет canonical closure/upvalue path.
- `weapon_tourniquet` возвращается медику при remote removal и пациенту при
  self-removal, с сохранением 180-секундного цикла, downstream cleanup и ран.
- Namespaced native C:U items/AED и их Start/Input/Close сохранены для
  совместимости с намеренно включённым инвентарём
  (`zc_woundsystem_compat_hide_cu_inventory 0`), но по умолчанию слоты не
  отображаются ни у себя, ни у пациента.

Каждый namespaced `WSZC_RemoteMedicalAction` содержит явного пациента и typed
payload. Сервер проверяет двух разных живых игроков, дистанцию, активную пару,
схему, владельца native session и настоящий слот лекаря. Каждый external input
повторно проверяет дистанцию. Watchdog закрывает inspection/native/external
сессии при смерти, disconnect, потере цели и закрытии панели; self-treatment
packets вне remote не перехватываются.

## Аудит лечения и authoritative-полей (2026-11-07)

Медицинский mirror проверен по конечному результату в `ply.organism`, а не по
изменению C:U shadow. Исправлены:

- выбор и лечение культи после ампутации: дистальная ordinary wound видна
  бинту на remaining stump, arterial wound остаётся отдельной задачей жгута;
- ровно одна доза body-drugs в штатной instant-ветке и в защитном async
  `onProgress` (`SwepHealDepth == 0`); стандартный one-dose instant не изменён;
- прямой `BloodBagTake`: уменьшение `body.bloodVolume` отражается в `org.blood`;
- полная доза `antagonistAmount +50` → `org.naloxoneadd +1` (clamp `0..1`),
  успешный `INJECTION` → `org.needle = 1`, rejected/wrong-limb → без needle;
- native timed medicine: procoagulant выполняет immediate + последующие
  1-секундные шаги с кумулятивными значениями, уменьшая `internalBleed` и
  настоящие ordinary/arterial wounds на всех 17 зонах. Временный C:U shadow
  восстанавливается после каждого шага, поэтому outer mirror не повторяет дозу;
  delayed relief cream использует тот же путь, bridge mode делегирует native;
- отрицательный C:U limb-bleed delta теперь уменьшает сами `org.wounds`, а не
  только временный `org.bleed`; специальные bandage/tourniquet delta по-прежнему
  обнулены и не применяются дважды;
- многоразовый жгут: 180-секундный цикл фиксации, штатное снятие возвращает один
  `weapon_tourniquet` и очищает status/visuals. До срока восстанавливаются только
  сохранённые раны (новые повреждения остаются), после срока раны остаются
  закрытыми. Повторный клик не дублирует SWEP, активный application site не
  принимает второй жгут, reset очищает цикл без выдачи предмета;
- fracture timer соответствует canonical C:U remaining time (`100 → 0`), а
  лечение меняет настоящие limb/neck/chest fields и `brokenribs`. Естественная
  ZCity-регенерация не заменяется второй физиологией. Для `SPLINTED` сохранены
  native износ `0.025/s`, fracture multiplier ×2.5 и joint timer ×2; expiry/reset
  очищают статус, а снятие вывиха проходит только через анатомический anchor.

Регрессия `tools/tests/test_medical_regression.py` читает canonical ZCity
WoundBridge и native C:U definitions прямо из исходных ZIP. Она проверяет
instant/async `SwepHeal`, настоящий `BloodBagTake`, naloxone, chest drain,
20 timed steps, fractures/dislocations/splint, ранний/зрелый tourniquet removal,
повторное использование и native receiver replay, а также отсутствие двойного
расхода или лечения. Это offline Lua regressions; финальная проверка в живом GMod остаётся
обязательной для engine/net/ragdoll поведения.

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
   Для бинта отключённый `WoundSystem_LimbTick` больше не является потерянным
   звеном: его `bandageSlowAmount` преобразуется в уменьшение severity реальных
   обычных `org.wounds` на выбранной конечности. Артериальные раны бинт не
   изменяет; их останавливает **только жгут**, который очищает запись
   `org.arterialwounds`, соответствующий artery-флаг и синхронизирует нативные
   `wounds` / `arterialwounds` / `Tourniquets`. Активный жгут хранит отдельный
   backup обработанных wound entries на `ply._WSZCTourniquetCycles`. Через 180
   секунд `TickTourniquets()` фиксирует результат и удаляет backup; автоматически
   статус не снимается. Штатный removal receiver возвращает один
   `weapon_tourniquet`, удаляет только выбранный visual у player/current ragdoll,
   очищает downstream flags и повторный клик игнорирует. Раннее снятие
   восстанавливает сохранённые severity/artery flags без удаления новых ран;
   зрелое оставляет раны закрытыми. Второй жгут на тот же активный site не
   расходуется, native `SPLINTED` и authority=0 replay делегируются C:U.
   Net-пакет `WSZC_BandageState`
   сообщает начальное/текущее обычное кровотечение, фактический процент его
   остановки и отдельный остаток артериального. Мини-игра рисует `STOP N%` и
   кольцо; при открытой артерии капля не скрывается, а после остановки обычных
   ран появляется подсказка `TOURNIQUET`. При artery-only ране прочность бинта
   не расходуется. `isBandaged` не блокирует повторный бинт, пока выбранная
   конечность кровоточит. Для настоящих ZCity-бинтов расход теперь такой же,
   как в оригинальном `SWEP:Bandage`: из `swep.modeValues[idx]` вычитается
   фактически удалённая severity, ограниченная остатком предмета. Например,
   severity 4 стоит 4 заряда независимо от ёмкости 40/150; виртуальный slot
   пересчитывается через `maxDur/def`, native `appliedLive` сохраняет штатный
   `onClose/AfterUse`, а второй `onProgress/Consume` не вызывается.
8. Не даёт C:U создать второй ragdoll: перехватывает её внутренний
   `ents.Create("prop_ragdoll")`, создаёт ZCity `hg.Fake`, зеркалит
   `body.unconsciousRagdoll` и защищает ZCity-ragdoll от удаления при wake.
9. Добавляет в круговой селектор ZCity кнопку «Проверить травмы», которая
   открывает готовую панель осмотра C:U, а не новый самописный интерфейс.
10. Синхронизирует `org.otrub` в `WoundSystemUnconscious`, иначе гейт
    `OpenHealthHUD()` мог навсегда заблокироваться после выключения физиологии C:U,
    и сбрасывает шрапнель при респавне (в том числе после `LoadPlayerPersistData`
    при переходе между картами).
11. Добавляет в WoundView настоящую 16-ю часть `neck`, а не рисует статичный
    mockup. Исходный head alpha сначала обрезается на head/neck, затем обе
    части независимо калибруются по зелёному эталону. Neck один владеет швом
    `y=317`; его интерактивность и отдельное состояние сохраняются.
    `EnsureNeckLimb` вставляет часть в нативные `Limbs`, инициализирует
    `GUIState.HoverAnims/LastHoverStates`, а `EnsureNeckClientState` — полный
    `PlayerLimbs.neck`. Hit-test и tooltip в `PostDrawHUD` показывают `Neck`,
    `Skin: N%`, `Muscle: N%`; стандартные action points и иконка перелома C:U
    работают на шейном state. `org.skull`, `Bip01_Neck1` и `neckartery`
    маршрутизируются на neck, а `head.dmg` удалён, чтобы не было второго
    перелома на голове. Сервер оборачивает C:U `InitPlayer`, добавляет отдельный
    `PlayerSpawn` timer и force-sync для уже подключённых игроков: первая жизнь
    не остаётся с неинициализированными частями. Родные ZCity HUD, таймер и
    нижние слоты продолжают рисоваться своими аддонами.

## Шрапнель: общий протокол, раздельные источники

Поле `state.shrapnel` в `PlayerLimbs` остаётся общим счётчиком для родной
мини-игры. Количество по источникам отдельно хранится в
`org.wszc_shrapnel_sources[limbId]`: `shotgun`, `blast`, `glass` (и `legacy`
для старых сохранений). Второй мини-игры нет: после снятия блокирующей повязки
`REMOVE SHRAPNEL` открывает один и тот же `BuildShrapnelSession()`. Если осколок
закрыт повязкой, guarded native receiver не снимает её кликом: он закрывает
старую native-сессию и запускает WSZC reverse-bandage. Только 360° движения в
обратную сторону вызывают `RemoveBandageForShrapnel()`; виртуальный рулон не
расходует инвентарь и пинцет. После закрытия unwrap следующий клик идёт по
обычному нативному пути извлечения.

| Источник | Правило | Откуда перенесено |
| --- | --- | --- |
| Подтверждённый дробовик | 3–5 фрагментов на фактически поражённом limb (с учётом лимита `ShrapnelPieceCount = 5`), блокируется HEV-шансом | `Fn.AddGunshotShrapnel` из обработчика урона C:U (в authority-режиме он больше не вызывается) |
| Взрыв | на фактически поражённом допустимом лимбе: `raw≥20` 60 %, `raw≥40` 50 %, `raw≥70` 40 %, до 3 осколков | ветка `DMG_BLAST` в `WoundSystem_Damage` |
| Стекло | +1 за удар рукой/ногой по стеклу; только этот источник remap-ится на `hand_L/R` или `foot_L/R` (стоячий игрок, brush `func_breakable_surf`, ragdoll-коллизии) | отсутствовало: в ZCity хук `sv_input.lua:441-446` закомментирован, `WB.SurfaceCut` пишет только skin/bleed |

Обычная пуля не создаёт осколков. `DMG_BUCKSHOT` сам по себе тоже не является
доказательством дробовика: нужен дробовый ammo/класс оружия/многопеллетный
выстрел. Настоящий ZCity PhysBullet обычно приходит с `DMG_BULLET`, ammo `-1` и
`inflictor = attacker`, поэтому проверяются также attacker active weapon,
known/family class (`spas12`, `xm1014`, `saiga12`, `remington870`, KS-23, M590,
TOZ/doublebarrel), `Primary.Ammo`, `game.GetAmmoName` и pellet count. Стекло
остаётся независимым источником; пистолет по-прежнему не проходит проверку.
`ShrapnelSpawnLimb` вызывается только для `glass`: shotgun/blast не сводятся к
кистям/стопам и остаются на фактическом `head/thorax/abdomen/arm/.../foot`.

Сырой урон снимается **до** `dmginfo:ScaleDamage(0.15)` внутри обёртки
`homigrad-damage`, иначе пороги взрыва никогда не сработали бы. Поверхности
берутся из `data["TheirSurfaceProps"]` через `util.GetSurfacePropName`, как в
`hg.velocityDamage` (ZCity `bleedSurfaces`). Лимит берётся из настоящего
`WoundSystem.Health.Constants.ShrapnelPieceCount` (не из внутреннего `Const`).

`org.wszc_shrapnel` — теневая копия для ZCity-кода. Пока осколок не извлечён,
`org.wszc_shrapnel_floor` удерживает повреждение лимба от регенерации; после
извлечения C:U пишет `state.shrapnel = remaining`, тень подтягивает новое
значение и блок снимается.

Каждые 0.5 с любой оставшийся фрагмент усиливает настоящую tagged ZCity-рану
(`wound.wszcShrapnel`) и добавляет боль в `avgpain/painadd/pain`. Кровотечение
поэтому переживает родной recalculate `org.bleed`. Severity такой раны
ограничено `8`, чтобы одного физического бинта хватало на её обработку. При
извлечении последнего осколка конечности удаляются только tagged-рана, source
map и irritation; обычные раны остаются. Откат роста:
`zc_woundsystem_compat_shrapnel_lodged_effects 0`.

Бинтировать конечность с фрагментом **разрешено**. Только после фактической
остановки обычного кровотечения `org.wszc_bandaged_shrapnel[limbId]` запоминает
закрытый фрагмент и кости с повязкой. Tagged external wound получает severity 0;
`EnsureLodgedWound()`, `TickLodgedShrapnel()` и `SyncShrapnel()` не создают её
заново под действующей повязкой. Попадание в заранее перевязанную конечность
помечается так же. Артериальная рана остаётся отдельной и требует жгута.

На конечности сразу появляется штатная C:U `infection.png`, а на covered-ране
`disinfectTime` обнуляется. Отдельный значок обработки `Icons.disinfected`
больше **не рисуется вообще**: native `AddHudIcon` пропускает только этот один
материал, поэтому infection/bleed/fracture и остальные медицинские иконки не
затрагиваются. Wrapper получает локальную C:U таблицу `Icons` через upvalue
(в том числе во вложенной функции), а точный material path служит fallback;
глобальный `_G.Icons`, которого в живой C:U нет, больше не нужен. Обычный
серверный `disinfectTime` и его сопротивление заражению
сохраняются — скрыт именно визуальный индикатор, а не эффект обеззараживания.
Серверный таймер идёт по анатомическим стадиям: **конечность 0–240 с → торс с
240 с → мозг с 420 с → смерть с 600 с**. Значения `state.infection` показывают
стадии штатным HUD, а `infectionSpeed=0` не даёт физиологии C:U добавить второй
таймер. На терминальной стадии вызывается тот же `ply:Kill()`, что использует
родная ZCity death logic, поэтому death/ragdoll hooks не обходятся.

Единственное лечение: **reverse unwrap 360° → извлечение → повторный полный
бинт**. Разматывание не приостанавливает таймер, извлечение само по себе не
убывает и не очищает инфекцию. Любое уменьшение `state.shrapnel` (даже одного
из нескольких фрагментов) создаёт отдельную `wszcShrapnelExtraction`-рану:
severity от `0.3`, затем `+0.015/с` (cap 6), плюс медленный рост
`painadd/avgpain/pain`. Она не удаляется вместе с lodged-раной. Только финальный
бинт после извлечения закрывает aftercare и очищает связанный инфекционный
источник на конечности/торсе/голове; даже уже свернувшаяся до нуля рана не
мешает этому завершению. Если повязки до извлечения не было, aftercare-рана и
боль всё равно создаются, но новой инфекции не возникает.

Повязка после **частичного** извлечения тоже закрывает текущую aftercare-рану и
останавливает внешнее кровотечение, но оставшиеся фрагменты сохраняют covered
infection timer. После следующего unwrap/extraction послеуход начинается снова;
очищение инфекции происходит только при повязке после ПОСЛЕДНЕГО фрагмента.

Обычный treatment budget бинта умножается на `3`, а `org.bleedingmul`
ограничен `0.55`. Конвары: `zc_woundsystem_compat_bandaged_shrapnel_infection`,
`zc_woundsystem_compat_shrapnel_infection_death_delay`,
`zc_woundsystem_compat_bandage_strength`,
`zc_woundsystem_compat_bleeding_multiplier`.

Complication-рана обрабатывается первой. Пока открыта обычная WSZC-перевязка
этой конечности (в том числе другим игроком), `ShrapnelBandageInProgress()`
приостанавливает только новый рост lodged severity/pain; существующее кровотечение
продолжается до реальной обработки. Нулевая tagged/extraction запись не удаляется
компакцией как мусор и не поднимается обратно до `0.5` между кругами. Дополнительные
`org.wszc_shrapnel_closed` / `org.wszc_shrapnel_aftercare_closed` сохраняют clot
даже после native `sv_blood.lua:131 table.remove(org.wounds,i)`; новый осколок,
новое извлечение и unwrap очищают marker и разрешают настоящую новую рану. После
извлечения `ShrapnelAftercarePending()` разрешает финальный server input даже
при нулевом внешнем кровотечении; artery-only бинт по-прежнему не расходуется.
В native ZCity-пути такой завершающий aftercare при нулевой severity тоже не
списывает заряд: расходуется только фактически удалённая severity.

Ампутация не является синонимом arterial bleeding. Native
`hg.organism.AmputateLimb()` создаёт arterial wound и ОТДЕЛЬНО ставит
`org.<limb>amputated`; обе структуры сохраняются. По `WB.ZLimbToWS` ZCity
ампутирует от предплечья/голени, поэтому C:U `dismembered` ставится только на
`forearm + hand` / `crus + foot`. Верхние `arm/thigh` — оставшийся stump. На нём
регистрируется `WSZC_AMPUTATION` (`order = -10000`, штатная
`casunknown-images/moodles/amputation.png`), который native
`Statuses.GetActive()` отдаёт перед bleed-статусами. Кровотечение удалённой
distal-зоны лишь для UI/выбора сайта проецируется на stump; severity, кость и
artery key в organism не меняются. `BestTourniquetLimb()` выбирает сначала
реально кровоточащий stump, затем обычную артерию, без подмены bleed значений.

Явный `hg_organism_clear` / `WB.ResetOrganism` полностью удаляет все фрагменты,
источники, tagged-раны, накопленную инфекцию, ZCity `bandaged_limbs` /
`tourniquets`, ампутации/раны и C:U residue. Дополнительно очищается
`org.brokenribs`: native `Org Clear` сбрасывает `org.chest`, но оставляет это
поле, иначе следующий `PushShadow()` снова включает иконку перелома рёбер.
Этот explicit-reset context отделён от внутреннего `ragdoll → standing`, где
сохраняется весь organism, включая текущий перелом.

Потеря сознания владельца сессии (`otrub/needotrub`, NW unconscious,
`consciousness < 0.4`) либо его смерть закрывает WSZC и нативные C:U мини-игры,
освобождает cursor/view/input и скрывает WoundView. `FakeRagdoll` и
`fake/needfake` — признаки posture, а не incapacity, поэтому в conscious
ragdoll интерфейс/мини-игры не закрываются. Если медик в сознании,
бессознательное состояние пациента его мини-игру не закрывает. На внутреннем
FakeUp `PlayerSpawn` сервер видит `OverrideSpawn == true` и сохраняет сессию;
на настоящем respawn принудительно закрывает все сессии и клиентские lock'и.

Вход в мини-игру — кнопка «Проверить травмы» → родная панель C:U → точка
`REMOVE SHRAPNEL`. Инструмент не требуется: `slotIdx = 0`, `hasTweezers = false`,
игра идёт «руками» (ветка `not MG.hasTweezers`), `ConsumeToolDurability` не
вызывается. Инвентарь C:U скрыт, ZCity SWEP'ы используют скрытый слот `6`.
Аналогично точка `FIX DISLOCATION` открывает ручное вправление вывиха.

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

### Подписки Мастерской (Steam Workshop)

Сам `woundsystem_zcity_compat` в Мастерской **не published**: это папка в
`garrysmod/addons/`, подпиской его не поставить.

Отдельный C:U для запуска **больше не нужен**: при отсутствии внешнего API
`wszc_vendor/bootstrap.lua` поднимает приложенные 71 Lua. Если внешний C:U уже
есть, embedded-файлы остаются неактивными. Не устанавливайте одновременно два
**внешних** экземпляра (папку `casualties_unknown_health_system_beta` и GMA
`3728573930`): два external loader-а по-прежнему дадут двойные хуки, таймеры,
net-сообщения и HUD.

Внешняя Workshop-версия может отличаться от приложенного ZIP; adaptive probe
использует её только при подходящем API. Три собственных C:U-шейдера
`shaders/fxc/*.vcs` уже находятся в коннекторе; **Simple Custom Shaders**
(`3440271589`) нужен только для дополнительных внешних C:U-эффектов. Подписка
`3728573930` теперь опциональна и полезна в основном ради звуков, которых нет
в исходном ZIP.

Контент ZCity подтягивается сам через `resource.AddWorkshop` при
`hg_loadcontent 1`: `3657897364` (main content), `3257937532` (distac content),
`3389728250` (Glide), `3389795738` (GTAV helicopters). На выделенном сервере эти
ID должны быть в `workshop.vdf` / `+host_workshop_collection`, иначе клиенты
увидят ERROR-модели и `missing material` в консоли. В исходном ZIP C:U лежат Lua, 3 шрифта и 3 скомпилированных шейдера —
звуков и материалов там нет. **В этой сборке UI самодостаточен**: 653 UI-материала
(`casunknown-images/*`, `woundsystem/*`, родные лимбы `middle/`+`outlines/`,
кадры руки, .vtf/.vmt), все 3 шрифта и все 3 собственных `.vcs` упакованы в
`woundsystem_zcity_compat/`. Материалы также зеркалируются в C:U full pack;
шрифты/шейдеры физически перенесены только в коннектор.
`tools/pack_ui_materials.py` разрешает все 125 ссылок на материалы из C:U/WSZC
Lua (36 алиасов: регистр, перенос спрайтов мини-игр, `_red`-вариант) и
assert'ом запрещает пропуски. Коннектор сам вызывает `resource.AddFile` для
всех 659 UI paths при `zc_woundsystem_compat_resource_downloads 1` и делит
`WoundSystem.Resources.Added` с C:U без дублей. Звуков в исходниках нет;
подписка `3728573930` может дать их и внешние Merc-шейдеры, но её нельзя
ставить одновременно с папкой C:U.

`zcity organs +`, `project hemogen blood`, `simple eye gore`, `zcitygore` для
системы **не обязательны**: компат к ним не обращается. При установке
`zcitygore` папкой нужен `zcity_gore_torso_workshopid` (по умолчанию `0`), из
Мастерской аддон определяет свой ID через `engine.GetAddons()`.

Обязательные конвары: `woundsys_enabled 1`, `zc_woundsystem_bridge 1`. Если
внешний C:U/WoundBridge отсутствует, bootstrap автоматически загружает embedded
runtime. Только если и он не смог инициализироваться, компат около 30 с
повторяет `WSZC.Setup()` и остаётся выключенным (`WSZC_Ready = false`), не
ломая ванильный `ply.organism`. Строка `runtime:` в `wszc_compat_status`
показывает `embedded`, `external` или `missing` для каждой зависимости.

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
| `weapon_bandage_sh`, `weapon_bigbandage_sh`, `weapon_medkit_sh` режим `1` | **bandage мини-игра**: цель выбирается по реальным `organism.wounds`/aftercare, а не по 4 Hz `isBandaged/bleed`-тени C:U; лечение идёт по мере намотки, `modeValues` списывается ровно на фактически удалённую severity (не на фиксированный процент C:U), с учётом остатка и без двойного Consume. После закрытия последней обычной раны native-сессия автоматически получает `completed`, проходит обычный `onClose/AfterUse` и удаляет overlay/virtual slot |
| `weapon_morphine`, `weapon_fentanyl` | **syringe мини-игра**: доза и расход идут по мере нажатия поршня |
| `weapon_naloxone` | **мгновенно**, хотя в ZCity есть `spec.mg` (oneshot) |
| `weapon_needle`, `weapon_medkit_sh` режим `5` | **мгновенно** (`INJECTION` / SALINE, apply) |
| `weapon_medkit_sh` режим `2` | **мгновенно** (MORPHINE oneshot) |
| `weapon_medkit_sh` режим `3` | **мгновенно** (BLOODCOAGULANT / SALINE vehicle) |
| `weapon_adrenaline`, `weapon_betablock`, `weapon_mannitol`, `weapon_thiamine` | **мгновенно** (body-эффект / SALINE vehicle) |
| `weapon_tourniquet` | **мгновенно через физический `WB.SwepHeal`**: прицельная PhysicsBone конечность (включая self-use ragdoll) scoped-маршрутизируется до `H.ApplyItemToBody`; затем реально закрывается ZCity arterial/ordinary wound именно на выбранной ноге/руке, а C:U apply/status выполняется best-effort. Native `false`/Lua-ошибка не отменяет лечение; при отсутствии обработанной раны предмет не расходуется. Штатное снятие возвращает один многоразовый SWEP и очищает visuals/status; до 180 секунд восстанавливает исходные раны, после — оставляет закрытыми. Повторный клик не дублирует предмет, второй жгут на активную конечность не расходуется. Бинт артерии не помогает |
| `weapon_painkillers`, `weapon_medkit_sh` режим `4`, blood bag и прочие спецы без `mg` | **мгновенно** (старая ветка `WB.SwepHeal`) |

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
  `WSZC_BandageInput` / `WSZC_SyringeInput`, шлёт `WSZC_MinigameAck`,
  `WSZC_BandageState` (обычный прогресс + остаток артерии) и
  `WSZC_SyringeState`, закрывает через `WSZC_BandageClose` / `WSZC_SyringeClose`
  и `WSZC_MinigameClose`.
- `session.startAmount`, `session.deferredUsed`, `onProgress`, `onClose` и
  причины закрытия (`completed`, `dead`, `respawn`, `disabled`, `needle_break`,
  `invalid_limb`, `replaced`, `target_gone`, `empty`, `user_cancel`) совпадают
  с контрактом `WB.StartMinigame()`.
- Родные C:U сессии bandage/syringe тоже учитываются в `HasExternalMinigame`
  и закрываются при `StopExternalMinigame`, чтобы две мини-игры не открылись
  поверх друг друга.
- AED не используется: у ZCity для него нет `spec.mg`. Shrapnel-мини-игра и
  dislocation-мини-игра вправления костей, наоборот, **родные C:U** и
  открываются из панели осмотра; их результат двусторонне синхронизируется с
  `ply.organism` (см. раздел ниже).

## Кнопка проверки травм в круговом селекторе

В `zcity.zip` уже есть хук `ZCity_WoundBridge_Inspect`, добавляющий пункт
`Examine Body` → `WB.OpenWoundView()`. Аддон **не рисует свой UI**: он
перехватывает `WB.OpenWoundView`, переименовывает и переподчиняет этот пункт на
«Проверить травмы» и вызывает `WoundSystem.OpenHealthHUD()` из C:U. Если штатный
хук отсутствует (в authority-режиме клиентский `WB.IsEnabled()` равен `false`,
поэтому ZCity может его не добавить), пункт добавляется нашим хуком
`ZCity_WoundBridge_Inspect_WSZC`; его идентификатор сортируется после штатного в
`SortedPairs()`, поэтому двух кнопок не бывает.

- Открывается именно родная панель здоровья/ран C:U, со своим HUD и
  мини-играми. Второго меню и HUD не создаётся; **инвентарь `1..5` и левый
  сканер `UNI-HEALTH` («панель unit») скрыты** runtime-фильтром отрисовки,
  потому что слоты и SWEP'ы привязаны в ZCity. Скрытый виртуальный слот `6`
  для ZCity SWEP'ов оставлен.
- Кнопка видна только живому `LocalPlayer()` при готовом аддоне: `WSZC_Ready`,
  `zc_woundsystem_bridge 1`, `woundsys_enabled 1`,
  `zc_woundsystem_compat_inspect_button 1`. Гейт на `WB.IsEnabled()` убран
  намеренно — в authority-режиме он `false` на клиенте. Эта кнопка проверяет
  **себя**; для пациента используется отдельная «Лечить игрока» и тот же WoundView.
- Перед открытием выдерживается `0.12 c`, чтобы круговое меню ZCity успело
  закрыться и не перехватить курсор.
- Команда `wszc_open_wounds` открывает ту же панель (для биндов и диагностики).
- `zc_woundsystem_compat_inspect_button 0` убирает и наш пункт, и штатный
  `Examine Body`.
- При закрытии мини-игры курсор не снимается, если панель C:U ещё открыта
  (`WoundSystemHealthHUDOpen`).
- Дополнительные `MEDICAL ASSESSMENT`, vital signs и selected-limb cards
  удалены по запросу владельца. Остаются прежние откалиброванные позиции и
  размеры doll/hitboxes, shaped outlines и нативный hover; отдельного
  `woundview_polish` конвара больше нет.

## Конвары

| Конвар | Откуда | Назначение |
| --- | --- | --- |
| `zc_woundsystem_compat_authority` | этот аддон, replicated | **По умолчанию `1`**: `ply.organism` авторитетен, C:U = UI/мини-игры/показатели/шрапнель. `0` — прежний мост, C:U владеет ранами. Переключается на ходу, карту перезапускать не обязательно. |
| `zc_woundsystem_compat_shrapnel` | этот аддон | `1` — единый `state.shrapnel` (пули, взрывы, стекло); `0` — не создавать осколки. |
| `zc_woundsystem_compat_glass_shrapnel` | этот аддон | `1` — осколки от стекла руками/ногами и ragdoll-коллизий. |
| `zc_woundsystem_compat_shrapnel_regen_block` | этот аддон | `1` — застрявший осколок блокирует регенерацию лимба ZCity до извлечения. |
| `zc_woundsystem_compat_shadow` | этот аддон | `1` — зеркалить травмы ZCity в HUD C:U (`BodyState`/`PlayerLimbs`). |
| `zc_woundsystem_compat_limb_bleed` | этот аддон | `1` — кровотечение по реальным ранам ZCity (per-bone); `0` — старое поведение «глобальный bleed на все лимбы». |
| `zc_woundsystem_compat_shrapnel_on_blocked` | этот аддон | `1` — считать попадание, чей `EntityTakeDamage` вернул `true` (ZCity пересылает его в `FakeRagdoll`, GMod отдаёт `took=false`). |
| `zc_woundsystem_compat_hide_empty_notice` | этот аддон | `1` — убрать надпись «Not completed - nothing was applied»; `0` — вернуть. |
| `zc_woundsystem_compat_disable_cu_fx` | этот аддон (client) | `1` — снять ВСЕ экранные/камерные/UI-эффекты C:U, оставить только эффекты ZCity; `0` — вернуть хуки C:U. |
| `zc_woundsystem_compat_disable_cu_blood` | этот аддон (client + server) | `1` — убрать декоративную кровь C:U и вернуть ванильную кровь ZCity/Hemogen; `0` — вернуть как было. |
| `zc_woundsystem_compat_shrapnel_only_shotgun_blast` | этот аддон (server) | `1` — осколки только от дробовика и взрыва, не от пистолетов/винтовок; `0` — старое поведение (любой `DMG_BULLET`). |
| `zc_woundsystem_compat_preserve_reset_structure` | этот аддон (server) | `1` — `reset organism` не поднимает персонажа и сохраняет структуру ZCity (`otrub`/`fake`/`canmove`), но полностью очищает раны/шрапнель/C:U residue; `0` — исходный ZCity reset. |
| `zc_woundsystem_compat_shrapnel_lodged_effects` | этот аддон (server) | `1` — любой неизвлечённый fragment наращивает tagged ZCity-рану, боль и кровотечение; `0` — отключить только этот рост. |
| `zc_woundsystem_compat_fullscreen_minigame` | этот аддон (client) | `1` — мини-игры бинта/шприца на весь экран; `0` — исходный квадрат ~760 px C:U. |
| `zc_woundsystem_compat_minigame_zoom` | этот аддон (client) | `0.85` — умеренно отдалённый размер мини-игры; диапазон `0.7..1.8`. |
| `zc_woundsystem_compat_native_minigame_zoom` | этот аддон (client) | **`0.85`** — умеренно отдалённые НАТИВНЫЕ мини-игры C:U (вправление, осколки, AED): квадрат 646 px при исходных 760 px; `GetRect()` и `Clip.Scale()` меняются вместе, поэтому изображение и hitbox совпадают. `1` возвращает 760 px; диапазон `0.4..1.2`. |
| `zc_woundsystem_compat_fullscreen_native` | этот аддон (client) | **`0`** — нативные C:U мини-игры в авторском размере. `1` — прежнее растяжение на весь экран; live-откат показал огромный обрезанный осколок и потерю нижней части раны. |
| `zc_woundsystem_compat_close_on_empty_click` | этот аддон (client) | **`1`** — клик по пустой области WoundView закрывает окно через `WoundSystem.CloseHealthHUD()`; кукла, 5 слотов, кнопки инструментов, action point, UNI-HEALTH и drag исключены. |
| `zc_woundsystem_compat_bandage_strength` | этот аддон (server) | **`3`** — множитель реального treatment budget бинта для ZCity ordinary wounds; не лечит артерии и не дублирует mirror. |
| `zc_woundsystem_compat_bleeding_multiplier` | этот аддон (server) | **`0.55`** — верхний cap `org.bleedingmul` для обычных ран; меньшее серверное значение не повышается, arterial formula не использует этот множитель. |
| `zc_woundsystem_compat_bandaged_shrapnel_infection` | этот аддон (server) | **`1`** — медленная внутренняя инфекция закрытых повязкой фрагментов; `0` отключает только рост инфекции, не цикл unwrap→extract. |
| `zc_woundsystem_compat_shrapnel_infection_death_delay` | этот аддон (server) | **`600`** — секунды от полного покрытия шрапнели на конечности до смертельной инфекции мозга без полного aftercare; торс = 40%, мозг = 70% таймера; диапазон `60..3600`. |
| `zc_woundsystem_compat_hand_cursor_scale` | этот аддон (client) | **`0.55`** — общий визуальный масштаб руки во всех C:U/WSZC мини-играх; применяется ровно один раз, native hitbox/rotation не меняются; центр спрайта пересчитывается вокруг pivot. Миграция revision 6 заменяет прежний `1.0`. Диапазон `0.2..1`. |
| `zc_woundsystem_compat_unitmenu_doll` | этот аддон (client) | `1` — 17 пиксельно трассированных частей WoundView (включая neck и отдельные abdomen/pelvis); `0` — родные спрайты C:U без добавленных шеи и таза. |
| `zc_woundsystem_compat_unitmenu_scale` | этот аддон (client) | **`0.25` — пиксельно точный чистый `1435.png` (тот же doll, что в 2222)**: screen `S=0.4155`, центр `(682.5,558.2)` при 1365×1079; сохранённый `woundsys_ui_scale` компенсируется, другие значения — пропорциональный размер, диапазон `0.1..0.8`. |
| `zc_woundsystem_compat_unitmenu_tint` | этот аддон (client) | `1` — белый `SetDrawColor` для `*_fill.png` (стандартный чёрный иначе умножается на чёрный `finalMiddle`). `*_edge.png` не трогается: обводка и её затемнение при наведении остаются за C:U. Оба sprite теперь трассируются из чистого `1435.png`: полный POT round-trip black/white масок = **0 различающихся пикселей**, 9 scanlines = точное совпадение. |
| `zc_woundsystem_compat_hide_minigame_text` | этот аддон (client) | `1` — убрать заголовок / счётчик / три строки инструкций / `Press RMB/ESC to exit` и верхнюю панель во **всех** 5 C:U + 2 WSZC мини-играх. **Тёмное затемнение заднего фона (`Clip.DrawBackdrop`) сохранено** — по запросу владельца «во всех мини играх было затемнение заднего фона как раньше». AED-статус `WoundSystemAEDStatus` убран только внутри активной мини-игры. **`minigameshrapnel.png` — передний слой раны, НЕ удаляется.** Иконки, осколок, рука, пинцет, `bandageOuter`, уведомления ZCity, красный death-текст, капли и `Icons.*` остаются. `0` — вернуть как было. |
| `zc_woundsystem_compat_handanim` | этот аддон (client) | `1` — человеческие `wszc/minigame/hand_idle.png` / `hand_click.png` 512×1260 в вертикальной CU-позе; `0` — родная рука C:U. |
| `zc_woundsystem_compat_handanim_scale` | этот аддон (client) | `1` — без дополнительного множителя поверх общего `hand_cursor_scale 0.55`; диапазон `0.2..1.5`. |
| `zc_woundsystem_compat_hide_minigame_hand` | этот аддон (client) | `0` — показывать руку; `1` — прежний режим без руки, со стандартной стрелкой. |
| `zc_woundsystem_compat_hide_minigame_cursor` | этот аддон (client) | `1` — скрывать OS-стрелку только во время активной мини-игры с рукой; hand draw и cursor watchdog применяют `blank`, не переключаясь периодически на `arrow`; на выходе и при `hide_minigame_hand 1` стрелка восстанавливается. |
| `zc_woundsystem_compat_hand_pivot_x` / `..._hand_pivot_y` | этот аддон (client) | `0.4` / `0.1` — точка захвата на коже между пальцами; native `MG.handDrawW/H` и хитбоксы не меняются. |
| `zc_woundsystem_compat_hand_pin_cursor` | этот аддон (client) | `1` по умолчанию: каждый Think синхронизирует `gui.MousePos()`, MG gameplay grip и видимый pivot, отключая C:U offset `100/400`, spring и collision-сдвиг; `0` — прежние HandPhysics/инерция/developer offsets. |
| `zc_woundsystem_compat_hand_mode_revision` | этот аддон (client) | Служебная миграция `6`: устанавливает scale `0.55`, zoom `0.85` и реальный cursor pin, сохраняет CU pivot/rotation/hitbox, затем не перезаписывает пользовательские настройки. |
| `zc_woundsystem_compat_dislocation_start` | этот аддон (server) | `35` — стартовое смещение кости в мини-игре вправления (было 100); диапазон `10..100`. Меньше = кость на экране и меньше ударов. |
| `zc_woundsystem_compat_hide_cu_inventory` | этот аддон (client) | `1` — скрыть 5 слотов C:U, их рамки, drag&drop и подбор мировых предметов; виртуальный слот `6` остаётся. |
| `zc_woundsystem_compat_hide_unit_panel` | этот аддон (client) | `1` — скрыть левый сканер `UNI-HEALTH v2.03` внутри WoundView. |
| `zc_woundsystem_compat_clamp_adrenaline` | этот аддон (client) | `1` — клампить `org.adrenaline` ≤2 и `org.painkiller` ≤1, чтобы камера ZCity не давала FOV-взрыв. |
| `zc_woundsystem_compat_organism_debug` | этот аддон | `1` — диагностика обёрток, шрапнели и медицинских дельт. |
| `zc_woundsystem_bridge` | ZCity | `1` — мост включён; `0` — полностью legacy `organism`. |
| `zc_wound_damage_scale` | ZCity | Множитель урона, передаваемого в C:U (только режим `authority 0`). |
| `zcity_wounds_collision_scale` | ZCity | Множитель collision/impact force (только режим `authority 0`). |
| `zc_woundsystem_minigames` | ZCity | `1` — ZCity вызывает external-minigame API для спецов с `spec.mg`; адаптер всё равно оставляет one-dose предметы мгновенными. |
| `zc_woundsystem_compat_minigames` | этот аддон | `1` — наша реализация мини-игр активна; `0` — instant-поведение без правки ZIP. |
| `zc_woundsystem_compat_debug` | этот аддон | `1` — диагностика найденных C:U upvalue и открытия/закрытия сессий. |
| `zc_woundsystem_compat_inspect_button` | этот аддон (client) | `1` — показывать «Проверить травмы»; `0` — скрыть кнопку и штатный `Examine Body`. |
| `zc_woundsystem_compat_remote_inspect_button` | этот аддон (client) | `1` — разрешить remote treatment и показывать «Лечить игрока» для живого player/ragdoll до 256 units; `0` — отключить функцию и кнопку. Команда `wszc_treat_player`. |
| `woundsys_enabled` | C:U | Должен быть `1` в обоих режимах. `0` отключает HUD, серверные обработчики мини-игр и протокол шрапнели. |

## Отдельные живот и таз в WoundView

Бывший единый нижний торс разрезан по фактическому шву эталона `1435.png`
(`y=520`): `abdomen` находится выше, новый `pelvis` — ниже. Это 17-й настоящий
элемент native `Limbs` и `PlayerLimbs`, со своими `_fill/_edge.png`, hitbox,
hover-подсказкой `Pelvis`, action point и серверными net-обновлениями. First-life
`InitPlayer` создаёт здоровое состояние, не копируя текущие раны живота; повторная
установка идемпотентна, отключение custom doll удаляет pelvis и neck из stock doll.

Медицинская власть остаётся у ZCity. Раны `Spine1/Stomach/Abdomen` маршрутизируются
в `abdomen`, `Pelvis/Hips/Hip` — в `pelvis`, поэтому бинт выбранной зоны не лечит
соседнюю. У ZCity существует только общий `org.pelvis` scalar: второй орган не
создаётся, а muscle-treatment применяет к нему ровно одну дельту. Проверки R69–R72
покрывают first-life, маршрутизацию трёх ран, раздельную перевязку и одиночную
дельту; R41 проверяет реальный Pelvis hitbox/tooltip.

## Исправления по скриншотам (полный экран, надпись, адреналин, дробовик)

1. **Мини-игры на весь экран.** C:U рисует мини-игру в квадрате
   `760 * Clip.Scale()` через `WoundSystem.MinigameClip.GetRect()`: эта функция
   задаёт и тёмный фон, и stencil/scissor, и позицию заголовка. Наш
   `cl_zcity_woundsystem_compat_layout.lua` подменяет **только** `GetRect()` на
   `0, 0, ScrW(), ScrH(), 0` (радиус 0 → `Clip.Begin` включает полноэкранный
   scissor). `wszc_cl_syringe.lua` теперь ставит `board` в `0,0` размером с
   экран и выражает оффсеты шприца/«переднего слоя» в долях высоты, а
   `wszc_cl_bandage.lua` увеличивает artwork в 1.2 раза. Симуляционные
   координаты и физика (`ScreenToSim`/`SimToScreen`) не менялись — только
   проекция на экран. **Важно:** с этого релиза полноэкранный `GetRect()`
   включается только когда активна наша WSZC-сессия бинта/шприца
   (`WSZC.WSZCMinigameActive()`). Раньше он применялся и к родным мини-играм
   C:U, из-за чего `MG.scale` в `cl_dislocation.lua` вырастал примерно вдвое,
   кость уезжала за верх экрана, а спрайты руки/кости перекрывали всё окно.
   Нативные игры получают исходный квадрат × `native_minigame_zoom`.
   Откат: `zc_woundsystem_compat_fullscreen_minigame 0`.

2. **«Not completed - nothing was applied».** Сообщение приходит из локального
   `Nothing()` внутри `onClose` в `sv_woundbridge.lua` (ZCity), когда игрок
   закрыл мини-игру до набора дозы. Коннектор фильтрует ровно этот
   `HUD_PRINTCENTER` текст через обёртку `Player.PrintMessage`, не трогая ZIP.
   В пересобранном `zcity_full_pack.zip` та же строка дополнительно убрана из
   `sv_woundbridge.lua`. Откат: `zc_woundsystem_compat_hide_empty_notice 0`.

3. **Эффект адреналина (радиальные полосы, тряска, дикий FOV).** C:U хранит
   `body.adrenaline` в шкале `0..100` и ставит `100` при огнестрельном ранении;
   ZCity использует `org.adrenaline` `0..2`, и `cl_camera.lua` умножает его на
   5 при расчёте FOV. Раньше медицинская дельта переливала `+100` напрямую →
   FOV уходил на сотни градусов. Теперь дельта масштабируется `*0.02` с
   клампом `2` (`painkiller` — `*0.01` с клампом `1`), `body.adrenaline` и
   `body.painkiller` зеркалятся из organism, плюс клиентский кламп лечит уже
   сохранённые «испорченные» организмы.

4. **Дробовик в ногу: кровь на всех лимбах.** `PushShadow` писал один
   глобальный `org.bleed` в каждый из 17 C:U limb'ов — поэтому HUD показывал
   капли и на голове, и на руках. Теперь `WSZC.LimbBleedMap()` разбирает
   `org.wounds[n][4]` (имя кости, например `ValveBiped.Bip01_R_Calf`) и
   `org.arterialwounds[n][7]` (`rlegartery`, `larmartery`, …), мапит их в
   limb id C:U и пишет `state.bleed` только туда. Внутреннее кровотечение
   остаётся в `body.internalBleeding` и больше не заливает весь силуэт.
   При `org.internalBleed > 0` оно дополнительно получает заметную красную
   `internalbleed_red.png` через native status `WSZC_INTERNAL_BLEEDING` ровно
   на `abdomen`; на `pelvis` пометка не дублируется, внешний `state.bleed`
   искусственно не создаётся, а при нулевом значении статус удаляется.
   Откат внешней разводки: `zc_woundsystem_compat_limb_bleed 0`.

5. **Дробовик в ногу: нет шрапнели.** Две независимые причины:
   * `homigrad-damage` (`sv_input.lua`) возвращает `true` и пересылает хит в
     `ply.FakeRagdoll`, поэтому GMod вызывает `PostEntityTakeDamage` с
     `took=false`; старый код такие хиты отбрасывал. Теперь инжекция идёт в
     `CaptureRawDamage` **до** этого `return`, а пост-хук остаётся fallback'ом;
     weak-key `WSZC.ShrapnelHandled` убирает двойной счёт.
   * В `sh_ammostuff.lua` у `12/70 gauge`/`slug` строка `dmgtype` закомментирована,
     поэтому `sh_luabullets.lua` шлёт пули как `DMG_GENERIC`, а проверялись
     только `DMG_BULLET`/`DMG_BUCKSHOT`. `IsBallisticHit()` теперь additionally
     читает `dmginfo:GetAmmoType()` → `game.GetAmmoName()` и `inf.NumBullet > 1`.
     `BONE_HITGROUPS` дополнен бедром/голенью/предплечьем, чтобы осколок ложился
     в ту ногу, а не в «ближайшую стопу».
   * Проверить: `zc_woundsystem_compat_organism_debug 1` → в логах
     `shrapnel +N on thigh_R (damage)`; `zc_woundsystem_compat_shrapnel 1`.

## Только эффекты ZCity, кровь ZCity, курсор и неподвижность в мини-игре

**Эффекты.** По умолчанию коннектор снимает все визуальные эффекты C:U:
`WoundSystem_PostProcess` (шейдер боли, bloom, sharpen, motion blur, туннель,
эффекты опиатов/ломки), `StaminaEffects`, `BlindEffects`,
`ChromaticAberration`, `SpinNausea*`, `Lobotomy*`, `BrainReverse*`, статик и
виньетки (`HUDPaintBackground`), moodles, self-talk («My muscles are burning…»),
**визуал** death screen (ввод респавна сохранён!), `CalcView`-тряску и
unconscious eye view, туман/чёрный скайбокс,
`BallisticAimKick`, инверсию управления и искажение текста
(`TextCorruption`). Отключается и звуковой слой C:U: looping medical audio,
CAS3-музыка, тиннитус, asystole, pain/death/growl-звуки, HEV, искажение чата
и «gunshot hearing» (`woundsys_audio_master 0`, `woundsys_music_enabled 0`,
`woundsys_tinnitus_volume 0`, …). **Сохраняются** панель ран `WoundDollAndPanel`,
`WoundSystem_UIRegistry`, обработка ввода панели и владелец курсора — C:U
продолжает работать как UI, мини-игры и протокол шрапнели. Обёртка
`WoundDollAndPanel` в `cl_..._layout.lua` только скрывает инвентарь и сканер
`UNI-HEALTH`; саму панель она не снимает. Оригиналы хуков
лежат в `WSZC.CUFxSaved`, поэтому `zc_woundsystem_compat_disable_cu_fx 0`
полностью возвращает эффекты. Фильтр повторяется каждую секунду, потому что
C:U пересоздаёт `EYEVIEW_CalcView` из своего `Think`.

**Кровь.** `cl_blood_effects.lua` рисует жёлтую «alien» кровь, лужи, следы и
потоки на телах, а `woundsys_fur_blood_models` — оверлей на моделях. Все эти
хуки снимаются, клиентские конвары крови выставляются в `0`. Важнее серверная
часть: `woundsys_replace_vanilla_blood 1` (дефолт C:U) вызывает
`Health.Config.ApplyVanillaBloodMode`, который ставит игрокам `DONT_BLEED` и
**глушит родную кровь ZCity / Hemogen**. `WSZC.DisableCUBloodReplacement()`
патчит эту функцию, возвращая `BLOOD_COLOR_RED`. Откат обоих пунктов —
`zc_woundsystem_compat_disable_cu_blood 0` **в консоли клиента и в консоли
сервера** (это два независимых конвара с одинаковым именем: клиентский
`CreateClientConVar` и серверный `CreateConVar`).

**Мини-игра бинтования/шприца.** Раньше персонаж продолжал ходить, а курсор не
появлялся. Три причины:
* `WoundSystem_ScreenClickerWatchdog` снимает курсор, когда
  `WoundSystemIsAnyWoundMinigameActive() == false`, а этот глобал C:U знает
  только 6 нативных мини-игр — наши namespaced копии в него не входят. Теперь
  глобал обёрнут: `original() or WSZC.MinigameActive()`.
* `WSZC_MinigameOpen` и `WSZC_BandageOpen`/`WSZC_SyringeOpen` приходят разными
  пакетами; старый `WSZC_MinigameClientWatch` успевал сбросить флаг и отпустить
  курсор до старта UI. Добавлена 1 секунда grace и повторное включение кликера
  в `Think`, если C:U его всё-таки забрал.
* Движение никто не блокировал. Клиентский и серверный `SetupMove` теперь
  обнуляют `forward/side/up`, `buttons`, `mousex/mousey` и горизонтальную
  скорость (падение по Z сохраняется), а `PlayerBindPress` глушит бинды ZCity
  (`+forward`, `+menu`, `slot*`, …), оставляя `toggleconsole`/`screenshot`.

## Шрапнель: только дробовик/взрыв и точная конечность

**Источники.** Раньше `IsBallisticHit()` возвращал `true` для любого
`DMG_BULLET` и даже для любого калибра вида «NxM mm», поэтому пистолеты и
винтовки сажали осколки. Теперь `IsShotgunHit()` требует положительного
подтверждения: ammo `12/70*`, `20/70*`, `23x75*` (все shotgun-SWEP ZCity —
xm1014, spas12, saiga12, remington870, roullet, doublebarrel_short), shotgun
класс или инфликтор/активное оружие с `NumBullet > 1`. Одиночный `DMG_BUCKSHOT`
без этих признаков недостаточен. Отдельная ветка `DMG_BLAST` даёт фрагменты от
взрывчатки отдельным вызовом. Патроны `9x19 mm`, `7.62x39 mm` и т.п. больше **не
дают** шрапнель. Откат: `zc_woundsystem_compat_shrapnel_only_shotgun_blast 0`.

**Конечность.** Прежде limb угадывался по ближайшей кости к
`dmginfo:GetDamagePosition()` — точке входа пули, которая у дробовика часто
лежит на другой части ragdoll, поэтому «оторвал ногу, осколок в руке». Теперь
приоритет у авторитетных данных ZCity: `org.dmgstack[hitgroup]` (ZCity сам
пишет туда урон и `CurTime()`), затем `ply:LastHitGroup()`, `ply.HitBones`,
и только потом позиция с жёстким порогом 55 юнитов. Если ни один источник не
дал конечность — осколок **не создаётся**, а не падает в случайный `thorax`.
Инъекция выполняется сразу после родного `homigrad-damage` внутри его wrapper:
`org.dmgstack` / `ply.HitBones` уже заполнены, а `return true` больше не может
подавить обработку. `PostEntityTakeDamage` остаётся fallback для сторонних
путей и обрабатывает `took == false`. Один DamageInfo, прошедший
player→FakeRagdoll или collision-proxy→player, дедуплицируется; proxy без
владельца/конечности НЕ помечается обработанным и не блокирует настоящий hit.

## `reset organism` не встаёт сам

`hg_organism_clear` и админское «Reset organism» очищают `ply.organism`:
`Org Clear / Main` сбрасывает `otrub/fake/canmove/alive`, а
`WB.ResetOrganism()` дополнительно вызывает `WB.RestoreRagdoll(..., false)` →
`hg.FakeUp(ply, true)` в `timer.Simple(0)`. Это и было «персонаж встал сам».

`WSZC.InstallResetStructureGuard()` оборачивает `hg.organism.Clear` и
`WB.ResetOrganism`: на время `ResetOrganism` `WB.RestoreRagdoll` подменяется на
no-op (иначе отложенный таймер поднял бы игрока уже после обёртки), а только
`otrub / needotrub / fake / needfake / alive / otrub_start / unconscious`
сохраняются и возвращаются после очистки. Травмы, blood/pain и `health`
очищаются как обычно. После восстановления повторно шлются
`hg.send_organism` / `hg.send_bareinfo` и обновляется shadow C:U.
При явном reset `SnapshotZCityStructure(..., false)` и `ClearAllShrapnel()` не
оставляют ни фрагментов, ни tagged-ран, ни source/irritation/C:U residue.
Очистка применяется к АКТУАЛЬНОМУ `ply.organism` после native reset; при
`false`/ошибке WB выполняется родной `hg.organism.Clear` fallback с traceback.
Death-ragdoll разрешается через `organism.owner`; штатный `reset_org` получает
владельца только на время callback, поэтому его `ent:Nick()` не вызывается на
ragdoll. Отдельный путь — родной `hg.FakeUp`: он вызывает `ply:Spawn()` с
`OverrideSpawn == true`, и обычный `Player Spawn → Org Clear` не должен стереть
медицину. Для этого `SnapshotRagdollOrganism()` cycle-safe копирует ВЕСЬ
organism (кроме entity `owner`) до native Clear, а `RestoreRagdollOrganism()`
возвращает native/third-party поля, wounds/arterialwounds, amputations,
шрапнель и infection после него. Настоящий respawn и explicit reset в этот
путь не входят. Откат: `zc_woundsystem_compat_preserve_reset_structure 0`.

## Камера в мини-игре

Обнуление `MouseX/MouseY` в `SetupMove` не останавливало вращение: GMod
применяет мышь в `InputMouseApply` / `CreateMove` и записывает
`cmd:SetViewAngles()` **до** `SetupMove`. Теперь при открытии мини-игры
запоминаются `LocalPlayer():EyeAngles()`, а `InputMouseApply` (с `return true`),
`CreateMove` и `SetupMove` возвращают их обратно. Сервер хранит те же углы в
`WSZC.MinigameSessions[ply].frozenAngles` и форсирует их в своём `SetupMove`,
поэтому модифицированный клиент тоже не крутит камеру.

## Шрапнель в ragdoll, стекло, осложнения и ввод

**Потеря при ragdoll.** C:U `InitPlayer()` выбрасывает `PlayerLimbs[ply]` и
создаёт новую таблицу на `Fake` / `FakeUp` / `WoundSystem_SpawnSync`. Старый
`PullShrapnel()` был односторонним (C:U → organism) и в этот момент записывал в
`org.wszc_shrapnel` нули — осколки исчезали. `WSZC.SyncShrapnel()` теперь
сравнивает ссылку на таблицу: если она новая, `WSZC.RestoreShrapnel()`
восстанавливает осколки ИЗ `ply.organism` (создавая недостающий limb через
`H.GetLimbState`), если та же — честно принимает результат извлечения из
shrapnel-мини-игры. Хуки `Fake` / серверный `Fake Up` / клиентский `FakeUp` /
`HG_OnWakeOtrub` дополнительно переутверждают состояние на следующем кадре;
`RestoreBones()` одновременно восстанавливает и amputation shadow.

**Стекло в ragdoll.** Раньше glass-обработчик висел `pre`-функцией на ZCity
хуке `Ragdoll Collide / organism` и дублировал его фильтры урона
(`speed >= 350`, `DeltaTime >= 0.25`) — лёгкое касание стекла рукой в
fake-ragdoll до него просто не доходило. Теперь это отдельный хук
`WSZC_GlassRagdoll`: порог 120, стекло определяется и по surfaceprop, и по
браш-сущности (`func_breakable_surf`, `MAT_GLASS`, material «glass»), владелец
ragdoll резолвится в т.ч. через `NWEntity("ply")`.

**Осложнения shrapnel-мини-игры.** C:U `BreakShrapnelGrasp()` (рывок /
повторное вдавливание осколка) добавляет `state.bleed` и `state.pain`, но наш
`PushShadow` каждые 0.25 с перезаписывал их из `ply.organism`, поэтому
кровотечения не было. Теперь shadow помнит, что сам записал
(`_WSZCExpectedBleed/Pain`), и скачок на конечности с `state.shrapnel > 0`
уходит в `WSZC.ApplyShrapnelComplication()`: `org.pain`, `org.bleed`, новая
запись в `org.wounds` с boneName этой конечности (её увидит `LimbBleedMap`) и
`org.wszc_shrapnel_irritation[limb]`. В `Org Think` irritation понемногу
наращивает кровотечение и боль, пока осколок не вытащен; при
`state.shrapnel == 0` счётчик сбрасывается.

**Мини-игра шприца.** `InputMouseApply` с `return true` подавлял не только
поворот камеры, но и `gui.MousePos()` — отсюда «рука не двигается» и мигающий
курсор. Теперь он обнуляет только `CUserCmd` и возвращает `nil`, а
`ViewAngles` фиксируют `CreateMove`/`SetupMove`. `+attack`/`+attack2`
пропускаются к UI (клик нужен для захвата инструмента; выстрела всё равно не
будет — `SetupMove` обнуляет кнопки). Watchdog курсора re-assert без проверки
`vgui.CursorVisible()`, а `WSZC_MinigameClientWatch` больше не роняет курсор
между сетевыми пакетами.

## Вывихи, переломы, инвентарь C:U и панель unit

**Вывихи — ручная мини-игра в WoundView.** У приложенной версии C:U уже есть
`lua/woundsystem/client/minigames/cl_dislocation.lua`: рука тянет смещённую кость
к суставу (`boneX/boneY` → `DislocationFinishX/Y`), сервер ведёт
`Sessions.Dislocation` и на успехе пишет `state.dislocated = false`,
`state.dislocationTimer = 0`. Кнопка `FIX DISLOCATION` рисуется самой C:U в
`WoundSystemDrawLimbActionPoint()`, когда `state.dislocated == true`. Проблема
была не в UI, а в авторитете: `PushShadow` каждые 0.25 с перезаписывал
`state.dislocated` из ZCity, поэтому вправление мгновенно откатывалось, а
свежий вывих приходил с `dislocationTimer = 0` (кость уже «на месте» — успех
на первом же пакете ввода, без ручного движения).

Теперь в `sv_zcity_woundsystem_compat_organism.lua`:

- `DISLOC_FLAGS` мапит один флаг ZCity на три C:U лимба (как `AnyDislocated()`
  в `WB.Sync`): `larmdislocation` → `arm_L/forearm_L/hand_L` и т.д.;
- `WSZC.SyncDislocation()` на НОВОЙ таблице `PlayerLimbs` (ragdoll/спавн)
  вызывает `WSZC.RestoreBones()` — вывихи и переломы восстанавливаются из
  организма и не теряются; на ТОЙ ЖЕ таблице изменение
  `dislocated true → false`, которого мы не писали
  (`_WSZCExpectedDislocation`), снимает флаг ZCity всей группы, добавляет
  `org.painadd + 10` и ставит `ply.fullsend`;
- `PushShadow` выставляет `state.dislocationTimer = WSZC.DislocationStartTimer()`
  (по умолчанию 35) у свежего вывиха и **не трогает** прогресс во время
  активной сессии; после успеха — `0`;
- `WSZC.DislocationActive()` читает `WSZC.CUSessions.Dislocation[ply]` (upvalue
  `Sessions` из `sv_health.lua`). Пока сессия открыта, `body.avgPain`
  ограничен 60: в C:U `DislocationPainBlock = 75`, а ZCity сразу добавляет
  `painadd + 35`, иначе каждый удар по кости блокировался бы. Реальная боль в
  `ply.organism` не меняется;
- клиентский `WSZC.MinigameActive()` и серверный `WSZC_MinigameServerLock`
  знают про нативную сессию: курсор, заморозка камеры и запрет
  движения/выстрела действуют и в этой мини-игре.

**Переломы — только ZCity.** Ванильный `sv_bone.lua` создаёт перелом как
`org.larm/rarm/lleg/rleg = 1`, рёбра — `org.brokenribs > 0`, `sv_pain.lua`
медленно регенерирует кость, а ZCity медицинские SWEP'ы через
`WSZC.ApplyMedicalDelta()` уменьшают `org.<limb>`. C:U получает лишь
`state.broken` и `state.boneHealTimer` как **отображение**: отдельной
мини-игры вправления перелома и своей симуляции костей нет. Порог иконки —
`0.85` (кость фактически сломана).

**Инвентарь C:U скрыт, слот `6` жив.** `cl_..._layout.lua` подменяет глобал
`WoundSystemInventorySlots` прокси: слоты `1..5` всегда `{type="empty"}`,
запись в них игнорируется, а запись/чтение `6` уходит в реальную таблицу —
именно туда `SetVirtualSlot()` кладёт инструмент для bandage/syringe от ZCity
SWEP'ов. `WoundSystem.Client.RequestInventoryMove` становится no-op, снимаются хуки
`WoundSystem_WorldItemInput` / `WoundSystem_WorldItemCheck` /
`WoundSystem_WorldItemDraw` / `WoundSystem_BodyUseHeldItemInput`, гасится
`WoundSystemDragState`.

**Панель unit.** Внутри окна осмотра C:U рисует левый сканер
`UNI-HEALTH v2.03` (`mats.compback`, 475×810) и 5 слотов инвентаря.
`WSZC.InstallCUHudFilter()` оборачивает хук `WoundDollAndPanel`, а
`HiddenRegion()` на время его выполнения глушит `draw.SimpleText`,
`surface.DrawTexturedRect( Rotated )`, `surface.DrawRect`,
`WoundSystemQueueLocaleTooltip` и `slot_*` direct-tooltips в зонах сканера и
слотов. Кукла, иконки лимбов, `FIX DISLOCATION` / `REMOVE SHRAPNEL`,
`action_*` tooltips, курсор и все мини-игры остаются нетронутыми. Установщики
идемпотентны и повторяются раз в секунду (C:U пересоздаёт хуки при hot
reload). Два конвара отката: `zc_woundsystem_compat_hide_cu_inventory`,
`zc_woundsystem_compat_hide_unit_panel`.

**Что исправлено после live-скриншотов.** В `3d7c793` обёртка писалась прямо в
`hook._t["HUDPaint"]["WoundDollAndPanel"]`; на сборках, где `hook.GetTable()`
возвращает защитную копию, это ничего не меняло, поэтому сканер оставался на
экране. Кроме того, рамки пяти слотов рисуются `surface.DrawOutlinedRect`
(`cl_health_gui.lua:4899`), а фильтр перехватывал только залитые прямоугольники
— пустые квадраты были видны даже при работающем прокси инвентаря. Сейчас:

- `hook.Add("HUDPaint", "WoundDollAndPanel", wrapper)` — поддерживаемая замена
  хука; чтение оригинальной функции всё ещё идёт через `hook.GetTable()`;
- обёрнуты `surface.DrawOutlinedRect` и `draw.RoundedBox`; установщик больше не
  требует существования `WoundSystemQueueLocaleTooltip` — опциональные
  C:U-глобалы патчатся отдельно, с повтором раз в секунду;
- `HiddenRegion()` учитывает `woundsys_ui_scale` и пропускает по-настоящему
  полноэкранные квады (тёмный фон WoundView);
- `PreDrawHUD` / `PostDrawHUD` — запасной контур на весь кадр HUD, если C:U
  перерегистрировала хук под другим именем и `InstallHudFilter()` вернул
  `false` (`WSZC.CUHudUseFallback`). В штатном режиме он выключен, чтобы не
  глушить элементы HUD ZCity, попадающие в те же области экрана;
- пока активна любая мини-игра, `WoundDollAndPanel` вообще не вызывается: кукла
  и `FIX DISLOCATION` больше не наслаиваются на кость.

**Предметы в руках.** `cl_..._minigames.lua` добавляет `PreDrawViewModel` и
`PreDrawPlayerHands` (возврат `true`) плюс однократное `SetNoDraw(true)` на
viewmodel в Think, пока `WSZC.MinigameActive()`. ZCity SWEP (бинт, шприц,
шина) больше не рисует своё 3D-содержимое поверх 2D мини-игры; после закрытия
`SetNoDraw(false)` возвращается.

**Размер вправления, число и высота целей.** `cl_dislocation.lua` считает
`MG.scale` из ширины клипа, а сервер кладёт кость на
`DislocationFinish + timer * DislocationStartSpread (5)` в случайном направлении
±60°. При `timer = 100` и полноэкранном клипе кость уходила на ~660 sim-единиц
вверх и оказывалась за верхом экрана; интерфейс выглядел «огромным», а
дотянуться до кости было нельзя. Теперь:

- `WSZC.WSZCMinigameActive()` отделяет наши сессии от
  `WSZC.NativeMinigameActive()`; только первые получают полный экран. Нативные
  получают исходный квадрат C:U, дополнительно уменьшенный
  `zc_woundsystem_compat_native_minigame_zoom = 0.75`;
- `WSZC.DislocationStartTimer()` = `zc_woundsystem_compat_dislocation_start`
  (по умолчанию 35) вместо жёстких 100 — кость рядом с суставом, одно короткое
  перетаскивание вместо десятков «вправлений»;
- `WSZC.AnyDislocation(org)` капит теневой `avgPain` до 60 всё время, пока флаг
  вывиха стоит (C:U проверяет `DislocationPainBlock = 75` и на старте сессии, а
  не только во время неё);
- `WSZC.MinigameActive()` включает ВСЕ нативные мини-игры C:U, поэтому курсор,
  заморозка камеры и запрет движения действуют и в dislocation/shrapnel/AED.

**Рука и курсор.** `sh_handphysics.lua` добавляет к цели мыши шум боли
(`pain * shakeX/shakeY`, до ±120 px по X), а спрайт руки 512×1260 при
`BaseScale() = 1.7 * 1.2` был выше экрана — отсюда «рука сходит с ума» и
невозможность взяться за бинт. `WSZC.StabilizeHandPhysics()` обнуляет
`pain`/`shakeX`/`shakeY`, ограничивает `maxLength = 45`, а
`WSZC.HandCursorScale()` (конвар, 0.45) уменьшает сам спрайт в
`wszc_cl_bandage.lua` и `wszc_cl_syringe.lua`. Курсор продолжает
переутверждаться каждые 0.15 с через `SetScreenClickerOwned(true)` +
`gui.EnableScreenClicker(true)`.

## Ограничения

- Режим `authority 1` не обещает полной 1:1 vanilla-эквивалентности Organs+:
 Organs+ не ссылается на `WoundBridge/WoundSystem`, а `hg.send_organism` шлёт
 фиксированный набор полей. Локальные счётчики, эффекты глаз, debug и кнопка
 работают; часть «берсерк/стимуляция» завязана на поля, которые в bridged
 `Org Think "Main"` не обновлялись и в vanilla-ветке тоже могут не
 обновляться. Vanilla-поведение без активной C:U-интеграции достигается
 `zc_woundsystem_bridge 0` + `woundsys_enabled 0`, но тогда исчезают панель и
 мини-игры (сам embedded loader при этом может оставаться загруженным).
- C:U-инвентарь скрыт и при самоосмотре, и в чужом WoundView: ZCity мини-игры
 используют виртуальный слот `6`, а расходуемые предметы применяются на пациента
 штатными ZCity SWEP. Пять native слотов появляются только при явном
 `zc_woundsystem_compat_hide_cu_inventory 0`. Переломы отображаются иконкой,
 но целиком считаются/лечатся ванильной ZCity.
- Remote treatment переиспользует WoundView, а не добавляет в C:U отдельный
 renderer. Его engine/net/ragdoll поведение нужно проверить на двух живых
 клиентах: offline fixtures не являются таким тестом.
- В C:U одна action-точка на лимб: если на конечности одновременно есть
 осколки и вывих, приоритет остаётся у `REMOVE SHRAPNEL`; после извлечения
 осколков появится `FIX DISLOCATION`. Радиальный пункт ZCity
 `hg_fixdislocation` работает независимо от WoundView.
- Скрытие инвентаря отключает и подбор мировых медпредметов C:U (`E`/`F`):
 медицинские предметы берутся через SWEP'ы и инвентарь ZCity.
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
- Проверено синтаксически (`luaparser`, 13 файлов), статически, на заглушечном
 Lua-рантайме и через canonical ZCity WoundBridge из исходного ZIP. Актуальные
 suites: `tools/tests/test_wszc_regression.py` (**155/155**, включая Lua 13/13,
 CRC/зеркало/манифест, pixel checks и 32 remote behavior tests),
 `test_gameplay_regression.py` (**93/93**), `test_bandage_regression.py`
 (**35/35**), `test_medical_regression.py` (**48/48**) и
 `test_compatibility_regression.py` (**26/26**: native/legacy/partial/missing API,
 independent feature gates, optional includes и Setup failure latch) — всего **357/357**.
 Remote M16 проверяет ragdoll range/watchdog; M17 прогоняет настоящий advanced minigame-server:
 `operator→patient`, один расход слота медика и запрет input вне дистанции.
 Medical-suite отдельно проверяет canonical
 instant/async medicine, timed effects, кровь, грудной дренаж, naloxone, кости,
 вывихи, splint и полный многоразовый tourniquet lifecycle. Скрипт сборки находится в `tools/build_packs.py`. На живом
 GMod-сервере ассистентом не прогонялось.
 Пользовательские live-скриншоты после `3d7c793` и `e70bfb5` показали, что
 предыдущие headless-тесты не доказывали скрытие в реальном клиенте;
 исправления выше сделаны по ним, но собственной live-проверки не было.

## Самодостаточный UI-контент

Исходный `casualites unknown.zip` (71 Lua, 3 шрифта, 3 шейдера) не содержит
`materials/` — именно поэтому интерфейс показывал ERROR и приходилось вручную
перекидывать текстуры из других файлов. `tools/pack_ui_materials.py` берёт оба
архива из `origin/main` и раскладывает в `woundsystem_zcity_compat/materials/`:

| Источник | Что даёт |
|---|---|
| `для переделывания интерфейса.zip` | 216 PNG: `zcity_delta/unitmenu/*`, `homigrad/handanim/*` (9 кадров руки), `bleedanim`, `limbs`, 159 moodles, traits, smiley |
| `для того чтобы все работало вместе материалы для UI.zip` | 362 файла: весь `casunknown-images/*` (18 старых лимбов `middle/`+`outlines/` с `_padded`, 43 иконки, 66 экранов, 43 предмета, мини-игры), `woundsystem/*`, 7 `.vtf`, 6 `.vmt` |
| генераторы `tools/build_unitmenu_materials.py` + `tools/build_minigame_hand.py` | 37 PNG куклы (34 limb + 3 status) + 2 человеческие руки (`wszc/unitmenu/`, `wszc/minigame/`) |

Итого **653 файл**. Плюс 36 алиасов, которые создаёт упаковщик: 25 точных
camelCase-копий (архив в lowercase, Linux-клиент регистрозависим) и 11
переносов — C:U ищет `handgraspidle1.png` / `minigameshrapnel.png` в папках
`dislocationminigame`, `shrapnelminigame`, `syringeminigame`, а архив держит их
только в `bandageminigame`; отдельно `screen/hemothoraxfill_red.png`.
14 PNG-дублей `(1)`, `(2)`, `(3)` из корня второго архива побайтово проверены и
пропущены. Скрипт сборки `zcity_full_pack.zip` зеркалирует те же 653 файл в
`garrysmod/addons/casualties_unknown_health_system_beta/materials/`, поэтому
аддон C:U тоже полный. Три `resource/fonts/*.ttf` и три `shaders/fxc/*.vcs`
перенесены из исходного C:U ZIP в коннектор побайтово; full pack удаляет их
старые копии из папки C:U. После добавления isolated runtime standalone ZIP
содержит **752 файла**: 653 материала, 6 C:U resource payloads, 88 Lua
(13 connector + 71 C:U + 3 WoundBridge + bootstrap), документацию и
`VENDOR_RUNTIME.sha256`. Исходные ZIP-аддоны не меняются; генератор
`tools/embed_runtime.py --check` подтверждает provenance всех 74 vendored Lua.

Для dedicated server `WSZC.InstallPortableResources()` регистрирует все 659
material/font/shader paths через `resource.AddFile`. По умолчанию включено
`zc_woundsystem_compat_resource_downloads 1`; `0` отключает регистрацию, если
сервер использует собственную раздачу. Повторный вызов и одновременный C:U
resource scanner не создают дублей благодаря общему `Resources.Added`.

Проверить в игре: откройте WoundView (`T`) — кукла, фон, иконки предметов и
статусов должны быть без розовых ERROR-квадратов; в консоли не должно быть
`missing material`. Если ERROR остался, сначала убедитесь, что распакована
именно эта сборка и клиент+сервер перезапущены.

### По live-скриншотам: кукла, фильтр HUD, осколки от стекла

Кукла из `unitmenu` шире родного квадрата C:U (760 px). `HiddenRegion()` —
фильтр, который убирает зелёный сканер слева и 5 слотов инвентаря — гасил
**любой** примитив в этих зонах, поэтому на скриншоте у куклы не было левой
руки и нижней части ног, а иконки осколков и `REMOVE SHRAPNEL` /
`FIX DISLOCATION` не рисовались. Исправлено:

* `WSZC.InstallMaterialTracker()` оборачивает `surface.SetMaterial` (C:U
  `SetGuiMaterial()` зовёт его напрямую) и запоминает текущий материал в
  `WSZC._DrawMaterialName`. Устанавливается **всегда**, обоими Think-хуками,
  даже при выключенных `hide_*` конварах.
* `WSZC.IsDollDrawMaterial()` пропускает через фильтр лимбы
  (`wszc/unitmenu/limbs/*`, родные `casunknown-images/middle|outlines/*`),
  иконки статусов (`wszc/unitmenu/status/*`, `casunknown-images/icons/*`) и
  `screen/uiPoint`. Всё остальное — сканер, `UNI-HEALTH`, слоты — по-прежнему
  скрыто; `WSZC.CUDeathVisualsHidden` по-прежнему гасит весь экран смерти.
* Размер куклы по умолчанию уменьшен `0.28 → 0.24`
  (`zc_woundsystem_compat_unitmenu_scale`), чтобы она не заходила в зоны
  слотов даже без трекера.
* Нативный оверрайд руки теперь работает через тот же общий трекер
  (`WSZC._OnSetMaterial`), без второго перехвата `surface.SetMaterial`.

**Осколки от ударов кулаками по стеклу.** Кулаки ZCity
(`weapon_hands_sh.lua:1653`) бьют браш `func_breakable_surf` через
`TakeDamageInfo`, но `PostEntityTakeDamage` для браш-сущностей приходит не на
всех сборках. Добавлен независимый `hook.Add("EntityTakeDamage",
"WSZC_GlassStrikePre", ...)` с общей функцией `WSZC.TryGlassStrike()`;
`return nil` никогда не блокирует ванильный урон, а 0.5-секундный
`glassCooldown` убирает дубли, если сработали оба хука. Резолвинг игрока
ослаблен: у SWEP-кулаков нет `.organism`, поэтому теперь пробуются
`OwnerOf(striker) or OwnerOf(attacker) or OwnerOf(inflictor)`. Путь не зависит
от `zc_woundsystem_compat_shrapnel_only_shotgun_blast` (тот фильтрует только
пули/дробь). Диагностика: `zc_woundsystem_compat_organism_debug 1` → в консоль
`[ZCity/CU compat] glass strike: ent=... ply=... limb=...`. Обязательные
конвары: `zc_woundsystem_compat_shrapnel 1`,
`zc_woundsystem_compat_glass_shrapnel 1`, `zc_woundsystem_compat_authority 1`.

**Кровь hemogen не трогалась.** `project hemogen blood.zip` содержит 123 файла
(`lua/` + `data_static/`) и **не содержит `materials/`**: аддон ссылается на
`advancedblood/sprites/*` и `advancedblood/decals/*`, которых нет ни в одном
архиве репозитория. Розово-чёрные квадраты на скриншоте — это ERROR-текстуры
самого hemogen, а не компата. Ни один файл аддона, ни один его хук или конвар
этой сборкой не изменён; compat к `advancedblood/*` не обращается. Чтобы их
убрать, нужно либо докачать материалы hemogen (отдельный архив/Workshop),
либо отключить аддон — скажите, какой вариант, и сделаю точечно, не трогая
остальное.

### По live-скриншотам №2: слоты, мини-игры на весь экран, бег после ресета

**Белые пустые квадраты слотов.** В прошлой сборке `IsDollDrawMaterial()`
пропускал через `HiddenRegion()` ВСЕ примитивы, пока «текущим» числился
материал лимба. Рамки 5 слотов — это `surface.DrawOutlinedRect` **без**
`surface.SetMaterial`, поэтому они унаследовали последний материал куклы и
стали видимыми (скриншоты 3/4). Разделили фильтр:

* `HiddenRegionRaw()` — геометрия зон; используется для `DrawOutlinedRect`,
  `DrawRect`, `draw.RoundedBox`, `DrawLine`, `DrawPoly`. Рамки слотов и чёрная
  подложка `REMOVE SHRAPNEL` снова гасятся.
* `HiddenRegion()` — `HiddenRegionRaw()` + whitelist материала; используется
  только для текстур (`DrawTexturedRect`, `DrawTexturedRectUV`,
  `DrawTexturedRectRotated`) и текста (`draw.SimpleText`,
  `draw.SimpleTextOutlined`). Лимбы, иконки статусов, `uiPoint` и сама надпись
  `REMOVE SHRAPNEL` / `FIX DISLOCATION` остаются видимыми.
* `CUDeathVisualsHidden` по-прежнему имеет высший приоритет в обеих функциях.

**Мини-игры: WSZC на весь экран, нативные C:U в авторском размере.** Две наши
мини-игры (бандаж/шприц) получают full-screen `Clip.GetRect()` через
`zc_woundsystem_compat_fullscreen_minigame 1`. Нативные C:U (shrapnel,
dislocation, AED) **по умолчанию НЕ растягиваются**:
`zc_woundsystem_compat_fullscreen_native 0` и
`zc_woundsystem_compat_native_minigame_zoom 0.85` дают умеренно отдалённый квадрат
646 px вместо исходных 760 px; `1` возвращает прежний размер. Причина — live-откат: `fullscreen_native 1` умножал `Clip.Scale()` на
`NativeFullscreenK()` (до 2.2×), из-за чего осколок 26×138 превращался в
огромный обрезанный чёрно-оранжевый спрайт, а нижняя часть раны уходила за
экран («я осколок рожаю или че, где нижняя часть откуда он достается?»).
`fullscreen_native 1` оставляет прежнее растяжение доступным как опцию.

**Бег после травмы и «Reset organism».** `RESET_KEEP` сохранял не только
«лежачую» структуру, но и `canmove`, `stun`, `consciousness`, `brain` — то есть
штрафы движения от травмы переживали ресет, и ZCity / `HG_MovementCalc_2`
навсегда оставляли скорость ходьбы. Теперь сохраняются только `otrub`,
`needotrub`, `fake`, `needfake`, `alive`, `otrub_start`, `unconscious`
(персонаж по-прежнему не встаёт сам), чтобы снова можно было быстро бегать, а `WSZC.ClearMovementPenalties()`
явно снимает `canmove=false`, `stun`, `pain` и числовые повреждения в
`org.legs`. Вызывается во всех трёх путях: `hg.organism.Clear` стоя,
`hg.organism.Clear` лёжа и `WB.ResetOrganism`.

**Скриншот 5.** «I don't want to experience this EVER AGAIN!» — это
статусное сообщение ZCity (`sh_status_messages.lua:219`), а не экран смерти
C:U; красные капли на груди/животе — иконки кровотечения WoundView. Компат их
не рисует и не глушит, это штатный ZCity/C:U HUD.

### По live-скриншотам №5 и №6: наша анатомия, стандартный чёрный, обводка по форме лимбов

**Кукла = приложенное эталонное фото.** Запечённые позиции 15 слоёв архива
давали широкое «пальто» с короткими ногами, поэтому
`tools/build_unitmenu_materials.py` больше не доверяет им: введён явный
`HUMAN_LAYOUT` (маленькая голова, узкий короткий торс, тонкие руки T-pose, длинные узкие ноги,
компактные целые стопы, симметрия пар (вертикальные швы сняты с нативной куклы `Screenshot_2-10.png`)). Каждый слой обрезается по жёсткому порогу
alpha >96 (иначе `r_foot.png` с прозрачной левой половиной давал стопу-полоску),
масштабируется LANCZOS в свою ячейку **с отступом `EDGE_PAD_MIN=6`** и эрозируется
на 3 px — тонкие зазоры шеи, плеч, талии, локтей, коленей и щиколоток
сохраняются. **Стандартный чёрный `(0,0,0)`** — ровно RGB исходных слоёв
архива; шифер `(42,56,60)` отклонён live. **Обводка по форме каждого лимба**:
`mask - MinFilter(mask, 9)` повторяет контур головы/рук/ног как родные
`casunknown-images/outlines/*`, при этом ни один белый пиксель не касается
границы прямоугольного спрайта (assert в генераторе `worst == 0.0`).
Отменены и per-limb кольца `be9c0b5` («конструктор»), и единый `outer_band`
`1da8b4a`, и пустая обводка `b47a0cb`, и родные `middle/*`/`native_tint` —
анатомия осталась НАША. C:U умножает `matM` на чёрный `finalMiddle`, поэтому
`zc_woundsystem_compat_unitmenu_tint 1` ставит белый `SetDrawColor` ТОЛЬКО для
`*_fill.png`; `*_edge.png` намеренно не перекрашивается, чтобы `finalOutline` +
`HoverAnims` затемняли обводку при наведении штатно. **Реакция на наведение не
изменена.** 16 id лимбов, ховер-хитбоксы и `REMOVE SHRAPNEL` /
`FIX DISLOCATION` не изменились.
`WSZC.FindCULimbs()` получил кэш, запасные пути поиска (все хуки +
экспортированные таблицы C:U) и повтор в `PreDrawHUD`, чтобы геометрия не
терялась при поздней регистрации `WoundDollAndPanel` в живом клиенте.

**Лишний текст мини-игр; затемнение фона сохранено.** `zc_woundsystem_compat_hide_minigame_text 1`
убирает «Shrapnel extraction (1/5)», счётчик, три строки инструкций и
`Press RMB/ESC to exit` во всех 5 нативных C:U и 2 WSZC мини-играх, а также
чёрную верхнюю панель и полноэкранную подложку. **`minigameshrapnel.png` НЕ
удаляется** — это передний слой раны (нижняя часть, откуда достаётся осколок),
а не чёрная панель; `WSZC.IsMinigameGameplaySprite()` защищает рану, осколок,
руку, пинцет, `bandageOuter`, `Icons.*`. `Clip.DrawHeader`
перевызывается с пустыми `title/value/guide` и `panelAlpha = 0`, но **иконка
мини-игры остаётся**; `Clip.DrawExitGuide` глушится, **`Clip.DrawBackdrop` сохранён** — затемнение заднего фона во всех мини-играх;
`draw.SimpleText*` фильтруется по `WSZC.IsMinigameTextFont()` для
chrome-шрифтов **и AED-статуса** и только пока мини-игра активна. Уведомления ZCity,
красный death-текст, капли, белые иконки переломов, осколки и рука не
подавляются. `0` — вернуть как было.

**Человеческая рука = реальный курсор C:U.** Генератор использует реальные кадры
`homigrad/handanim`, поворачивает их пальцами вверх и сохраняет открытую ладонь
и кулак в `materials/wszc/minigame/`. По умолчанию `hand_pin_cursor 1`: каждый
Think `gui.MousePos()` записывается одновременно в `MG.handScreenX/Y`, orbit/grab
и видимый pivot; spring velocity, collision clamp и C:U offset `100/400` не могут
увести руку вниз. Idle/click и поворот сохраняются. `hand_pin_cursor 0` включает
прежние HandPhysics, боль и инерцию. Pivot `zc_woundsystem_compat_hand_pivot_x 0.4` /
`..._hand_pivot_y 0.1` — исходные CU-значения. Исходный canvas `512×1260`
рисуется с общим коэффициентом `hand_cursor_scale 0.55` и дополнительным
`handanim_scale 1`; пропорции и `rot` сохраняются. Центр вычисляется из
повёрнутого pivot, поэтому пальцы остаются на `MG.handScreenX/Y`; логические
hitbox'ы отдельно не меняются, экранного cap нет. Системный курсор скрыт в активной мини-игре
(`..._hide_minigame_cursor 1`), повторно скрывается при каждой отрисовке руки
и после КАЖДОГО срабатывания cursor watchdog, восстанавливается на выходе.
Watchdog больше не ставит `arrow` каждые 0.05 с поверх `blank`. Для старого
режима C:U с инерцией используется `..._hand_pin_cursor 0`; для обычной стрелки
без руки — `..._hide_minigame_hand 1`.

**Фон WoundView.** `WoundDollAndPanel` рисует полноэкранный `woundbg` с альфой
150, а `DrawConsciousnessBlackout` — чёрный квад поверх всего: отсюда
тёмно-красный затемнённый экран на четвёртом скрине. `HiddenRegionRaw()`
теперь гасит такой квад только когда `WoundSystemHealthHUDOpen == true`: мир
за куклой остаётся видимым, а blackout при потере сознания (когда HUD закрыт)
работает как раньше. `zc_woundsystem_compat_hide_woundview_backdrop 0`
возвращает подложку.

**Не тронуто по явному выбору:** белые иконки переломов/вывихов, красные капли
кровотечения, статусные надписи ZCity/C:U, `project hemogen blood`. Их можно
убрать отдельно, если попросите.

## Файлы

```text
woundsystem_zcity_compat/
├── addon.json
├── README.md
└── lua/autorun/
    ├── sh_zcity_woundsystem_compat.lua        # общий патч, authority, vanilla context, WSZC_Ready
    ├── client/
    │   ├── cl_zcity_woundsystem_compat_layout.lua     # full-screen GetRect(), единый scale, кламп адреналина
    │   ├── cl_zcity_woundsystem_compat_minigames.lua  # виртуальный слот, WSZC_* приём, загрузка копий
    │   ├── cl_zcity_woundsystem_compat_inspect.lua    # «Проверить травмы» → WoundSystem.OpenHealthHUD()
    │   ├── wszc_cl_bandage.lua               # namespaced-копия C:U bandage UI, full-screen
    │   └── wszc_cl_syringe.lua               # namespaced-копия C:U syringe UI, full-screen
    ├── server/
    │   ├── sv_zcity_woundsystem_compat.lua           # экспорты, guard урона, лечение, ragdoll
    │   ├── sv_zcity_woundsystem_compat_minigames.lua # external API, сессии, прогресс, закрытие
    │   └── sv_zcity_woundsystem_compat_organism.lua  # authority-режим: шрапнель, тень, vanilla-обёртки
    └── wszc_vendor/
        ├── bootstrap.lua                             # external-first + late fallback + client source sync
        ├── cu/                                       # 71 изолированный C:U Lua
        └── zcity/woundbridge/                        # 3 изолированных WoundBridge Lua
```

## Диагностика

Если строка «compatibility layer active» не появилась:

1. Выполнить `wszc_compat_status`, затем `wszc_compat_reprobe` после загрузки всех
   аддонов. Сохранить профиль, список contracts/features и `reason=...`.
2. `zc_woundsystem_bridge 1`, `woundsys_enabled 1`,
   `zc_woundsystem_compat_adaptive 1`.
3. `zc_woundsystem_compat_debug 1` и перезапустить карту.
4. Проверить `runtime:` в статусе. При отсутствии внешних
   `autorun/sh_health_init.lua` / `homigrad/woundbridge/` должно быть
   `cu=embedded zcity_bridge=embedded`; внешние API показываются как
   `external`. При `core=no` не отключайте adaptive: нужен ZIP сборки для
   адаптера, а не принудительный запуск несовместимых wrapper-ов.

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


## Live-скриншоты №5–6: остатки HUD слева и респавн

**Зелёный HUD слева.** После `e70bfb5` фон сканера (`mats.compback`) и его
текст исчезли, но на экране остались зелёная полоса сверху, две «лёгких»,
бицепс, ЭКГ и две полосы с пиксельным текстом. Причина: `cl_health_gui.lua`
рисует их не `surface.DrawTexturedRect` / `draw.SimpleText`, а

* `DrawRectUVInt()` → `surface.DrawTexturedRectUV` (бары, лёгкие, иконки),
* `surface.DrawLine` (ЭКГ `:4421-4438`, пять проходов толщины + glow),
* `surface.DrawPoly` (`DrawArcLine`, дуги unconscious-круга),
* `surface.DrawText` / `draw.SimpleTextOutlined` (резерв для других сборок).

`InstallDrawWrappers()` теперь обёртывает и их: для линии проверяются оба конца
и середина, для полигона — ограничивающий прямоугольник вершин. `HiddenRegion()`
по-прежнему не трогает куклу, иконки лимбов, `FIX DISLOCATION` /
`REMOVE SHRAPNEL` и `action_*` tooltips. Тесты `H15/H16/H17` и `D8`.

**«Кильнулся и не смог зареспавниться».** Корень — в `FX_HOOKS` предыдущих
релизов: `{ "HUDPaint", "WoundSystem_DeathScreenDisplay" }` удалялся вместе с
остальными эффектами C:U. Но в `cl_health_gui.lua:5716` внутри этого хука
находится единственный клиентский обработчик респавна:

```lua
if input.IsMouseDown(MOUSE_LEFT) then
    if not DeathScreen.clickDebounce and fadeElapsed >= 1.0 then
        DeathScreen.clickDebounce = true
        SetDeathScreenActive(false)
        WoundSystem.HealthGUI.SetScreenClickerOwned(false, "deathscreen_think_not_dead")
        net.Start("WoundSystem_PlayerRespawnRequest")
        net.SendToServer()
    end
end
```

а `sv_deathscreen.lua` в хуке `PlayerDeathThink` / `WoundSystem_BlockRespawn`
возвращает `false`, пока `ply.WoundSys_CanRespawn` не станет `true` — это делает
только `net.Receive("WoundSystem_PlayerRespawnRequest")`. Удалённый HUDPaint →
нет сообщения → респавн заблокирован навсегда, чёрный экран висит.

Исправление:

1. Хук **исключён** из `FX_HOOKS`; `WSZC.WrapCUDeathScreen()` заменяет его
   через `hook.Add` обёрткой, которая на время вызова ставит
   `WSZC.CUDeathVisualsHidden = true`. `HiddenRegion()` в этот момент
   возвращает `true` для ЛЮБОГО примитива (включая полноэкранный чёрный
   `surface.DrawRect(0,0,ScrW(),ScrH())` из `DrawDeathBackgroundVisuals`),
   поэтому визуал C:U не рисуется, а `SetDeathScreenActive`, `clickDebounce`,
   снятие курсора и отправка запроса работают как в ваниле. Флаг
   восстанавливается через `pcall`, даже если хук упал.
2. `WSZC_CUDeathRespawnFallback` — независимый Think-обработчик на случай,
   если C:U переименует хук или загрузится позже: через 1 с после смерти
   включает курсор и по ЛКМ один раз отправляет тот же net-запрос
   (через `pcall`), после респавна гасит курсор. Выключен, как только
   `WSZC.CUDeathScreenWrapped == true`.
3. Залипшие мини-игры больше не блокируют ввод мёртвого игрока:
   `WSZC.MinigameContextOK()` проверяет `LocalPlayer():Alive()` и
   участвует во всех трёх `*.MinigameActive()`; `PlayerDeath` и `PlayerSpawn`
   вызывают `WSZC.ClearAllMinigameState()` (7 таблиц `MG.active`,
   `MinigameHUDOpen`, `MinigameFrozenAngles`, `_ViewModelHidden`); серверный
   `WSZC_MinigameServerLock` сразу выходит для мёртвого `ply`, чтобы
   `PlayerDeathThink` получил свободный `CUserCmd`.
4. `ShutDown` возвращает оригинальный хук (`RestoreCUDeathScreen()`).

Практика: после смерти подождать 1 секунду и нажать ЛКМ. Полный возврат
визуала экрана смерти C:U — `zc_woundsystem_compat_disable_cu_fx 0`.

### По live-скриншотам №6: пять исправлений (`Screenshot_2-8`, `Screenshot_3-5`)

| Претензия | Что было не так | Исправление |
| --- | --- | --- |
| «рукой двигать не могу в бандаже» | `InputMouseApply` и `SetupMove` вызывали `cmd:SetMouseX(0)` / `SetMouseY(0)`. При `gui.EnableScreenClicker(true)` GMod питает `gui.MousePos()` из того же `CUserCmd` mouse delta — обнуление прибивало курсор к `(0,0)`, и `HandPhysics.Step()` видел нулевую цель. | Оба сеттера удалены. Заморозка камеры (`SetViewAngles`), нулевое движение/кнопки и `return nil` сохранены. Мышь доходит и до VGUI-курсора, и до мини-игры. |
| «я осколок рожаю или че, где нижняя часть откуда он достается?» | `minigameshrapnel.png` ошибочно сочли чёрной панелью и подавляли в `surface.DrawTexturedRect`; это **передний слой раны** (`cl_shrapnel.lua:421`, `cl_syringe.lua:540`). Плюс `fullscreen_native 1` умножал `Clip.Scale()` на `NativeFullscreenK()` до 2.2×, растягивая осколок 26×138 в огромный обрезанный спрайт и уводя низ раны за экран. | Подавление удалено полностью; добавлены `WSZC.IsMinigameWoundLayer()` и белый список `WSZC.IsMinigameGameplaySprite()` (рана, осколок, рука, пинцет, `bandageOuter`, `Icons.*`) в HUD-фильтре. `fullscreen_native` по умолчанию `0`, `native_minigame_zoom` `0.85` → квадрат 646 px; `1` → прежние 760 px. `text=all` убирает только заголовки/инструкции/чёрный chrome. |
| «почему шрапнель пропадает при вставании из рагдолла» | `RESET_KEEP` не содержал `wszc_shrapnel*`, поэтому `hg.organism.Clear()` стирал тень; а `PlayerSpawn` безусловно занулял organism и C:U limbs, перебивая `RestoreShrapnelSoon` (0/0.3 с) из-за неопределённого порядка хуков. | Три поля добавлены в `RESET_KEEP`; `CarryShrapnelShadow()`/`RestoreShrapnelShadow()` переживают и ветку `down=false`; `hook.Add("Fake"/"FakeUp"/"HG_OnWakeOtrub")` ставит `_WSZCRagdollTransitionUntil`; `WSZC.ReconcileSpawnShrapnel()` при переходе **восстанавливает** из авторитетного organism, а чистит C:U только на настоящем респавне. `SyncShrapnel()` больше не копирует свежую пустую таблицу limbs обратно в organism в том же тике. |
| «сделай wound view куклу не таким цветом, верни стандартный и обводку по краям тоже» | `(42,56,60)` + единый `outer_band` + прямоугольные `seam_lines` — отклонено live. | Выбор владельца: **`black_anatomy` + `native_outline`**. `_fill` = стандартный чёрный `(0,0,0)` исходных слоёв архива; `_edge` = тонкая линия по форме **каждого** лимба (`mask - MinFilter(mask, 9)`), вписанная с `EDGE_PAD_MIN=6`, поэтому ноль белых пикселей на границах спрайтов. Наша `HUMAN_LAYOUT` сохранена; `native_tint`/`middle/*`/`1da8b4a`/`b47a0cb`/рамки не возвращались. Hover `finalOutline`/`HoverAnims` сохранён. |
| «почему когда я нажимаю на пустую область wound view окно не закрывается» | В самом C:U нет generic outside-click close: `CloseHealthHUD()` зовётся только по клавише, смерти и респавну; `GUIState` — local `:1702`. | Добавлено новое WSZC-поведение: `WSZC.WoundViewEmptyClick(mx,my,s)` + `Think`-хук `WSZC_WoundViewEmptyClickClose` по переднему фронту ЛКМ вызывает `WoundSystem.CloseHealthHUD()`. Исключены кукла, 5 слотов, кнопки инструментов, action point, UNI-HEALTH, тултипы, drag, активная мини-игра, внешние меню и фокус ввода. Откат: `zc_woundsystem_compat_close_on_empty_click 0`. |

### По live-скриншотам №7: размеры всех лимбов по `Screenshot_3-6.png`

Правка **только про размер/пропорции 15 лимбов**. В `HUMAN_LAYOUT` все
`cx/cy/w/h` сняты с третьего скриншота (338×309): силуэт 262×277 px, линии
стыков `x = 28/50/99/134/188/225/266/289`, `y = 15/57/113/174/223/270/291`.
Эталон линейно перенесён в тот же габарит 101…1401 × 136…1364 в канвасе 1500,
поэтому общий масштаб куклы, hitbox'ы и посадка в HUD не меняются; пары R/L
симметричны (`cx_R + cx_L = 1500`), руки остаются в T-pose, стопы целые.

Что изменилось относительно прошлой сборки: `thorax` 263×335 → **250×262**
(был слишком высокий «квадрат»), `abdomen` 234×191 → **236×288** (был слишком
низкий), `forearm` 134 → **211** (был слишком короткий), `hand` 143 → **107**
(была слишком широкая), `crus` 95×253 → **84×220**, `foot` 105×105 → **80×100**
(были массивные «ботинки»), `head` 120×178 → **118×198**. 32 limb PNG пересобраны,
`wszc_unitmenu_geometry.lua` перегенерирован.

**Не тронуто по просьбе владельца:** стандартный чёрный `(0,0,0)`, обводка по
форме каждого лимба (`EDGE_PAD_MIN=6`, `EDGE_WIDTH=9`), hover `finalOutline`/
`HoverAnims`, мини-игры и `text=all`, рука, shrapnel и его сохранность при
рагдолле, закрытие по пустому клику, organism/authority и все конвары.
Правки будут продолжаться — следующий шаг только после свежих live-скринов.

### По live-скриншоту №8: вторая итерация размеров + чуть жирнее обводка

`Screenshot_4-5.png` показал, что после №7 верх куклы в живом GMod всё ещё
растянут, а бёдра сжаты. Сделана **только** ещё одна правка размеров/пропорций
15 лимбов и толщины обводки, больше ничего не тронуто:

- `head` 118×198 → **126×178** (ниже и чуть шире);
- `thorax` 250×262 → **250×232** (короче);
- `abdomen` 236×288 → **236×276**, сдвинут вверх `cy 705 → 649`;
- `thigh` 115×232 → **115×292**, сдвинут вверх `cy 965 → 933`;
- `crus` 84×220 → **84×222**; стопы, все 6 лимбов рук и T-pose без изменений.

Стыки по вертикали теперь `101 / 279 / 511 / 787 / 1079 / 1301 / 1401` в
канвасе 1500; габарит куклы, hitbox'ы и посадка в HUD не изменились. Доля
ног относительно корпуса выросла с `0.736` до `0.895`, что компенсирует
замеренный на live перекос (голова `18.0%` и грудь `26.7%` против эталонных
`15.2%` и `20.3%`, бедро `10.5%` против `17.8%`).

Обводка утолщена `EDGE_WIDTH = 5 → 9` (`MinFilter(mask, 9)`), то есть с
~0.9 px до ~1.7 px на экране при live-масштабе 0.43. По-прежнему **обводка по
альфа-форме каждого лимба**, без белых рамок вокруг PNG: `EDGE_PAD_MIN = 6`
удерживает контур внутри спрайта, проверка даёт `0.0%` белого на границах.

Чёрный `(0,0,0)`, hover `finalOutline`/`HoverAnims`, мини-игры, `text=all`,
рука, shrapnel, закрытие по пустому клику, organism/authority, конвары и весь
runtime-код **не изменялись**. Живой GMod агентом не запускался — принятие
только по fresh live-скриншотам.

Все пять правок проверены headless (71+ проверок, `ALL_LUA_OK`, пересборка материалов и обоих ZIP), но **живой GMod агентом не запускался** — принятие только по свежим live-скриншотам.


### По live-скриншотам №9: геометрия куклы + прежнее ТЗ четырёх точек (уточнено)

`Screenshot_2-10.png` — родная кукла C:U `EXPERIMENT UNIT-HEALTH V2.04`, её и
нужно было повторить («вот так сделай»). `Screenshot_1-9.png` — наша кукла в
том же HUD, где красными кружками отмечены **обе кисти и обе стопы**. Сделано
ровно две вещи, без лишних правок:

1. **Только размеры и положение 15 лимбов — попиксельно, без «~2%».**
   `Screenshot_1-10.png` (наша кукла после равномерного ×1.15) был отвергнут:
   «бля ну одинаково делай по размерам как на том скриншоте». Причина найдена
   в C:U `DrawSprite`: `drawW = mat:Width() * scaleMult`, `drawH = mat:Height()
   * scaleMult`. GMod грузит PNG в текстуру ближайшей степени двойки, поэтому
   `145×235` сообщает `256×256`, а `288×304` — `512×512`. Видимый лимб растёт
   по **POT(w)/POT(h)**, а НЕ по числам из таблицы: на live был торс `196 px`
   при предсказании `288·0.4155 ≈ 120 px`. Uniform-масштаб `w/h` оставляет
   каждый лимб в том же POT-бакете и поэтому ничего не лечит.

   Исправление — точная обратная калибровка по ОБОИМ живым скриншотам:

   * по `Screenshot_1-10.png` снята карта `S = 0.4155 px` на единицу канваса,
     центр `(682.5, 558.2)`; четыре независимые опорные точки сошлись в
     пределах 2 px: макушка `248`, шов шеи `346`, размах рук `391..975`,
     подошвы `869`;
   * по `Screenshot_2-10.png` сняты 15 экранных прямоугольников: швы
     `218 / 320 / 451 / 592 / 708 / 810 / 865`, голова `650..712`, торс
     `621..742`, руки `369..969`, ноги двумя сегментами;
   * для каждого лимба `cx = 750 + (target_cx − 682.5)/S`, `cy` аналогично,
     а силуэт вписан во внутренний бокс ровно `target/S` единиц канваса. Сам
     спрайт теперь имеет размер **степени двойки** (`128/256/512`), поэтому
     `mat:Width() == w` при любом округлении GMod и размер больше не зависит
     от POT-скачков. `hoverW/hoverH` несут видимый бокс: C:U берёт
     `limb.sourceW/sourceH` для hit-теста, и подсовывать туда POT-спрайт
     нельзя (`ApplyDoll` + `BuildUnitmenuMaterials`, две строки).

   Симуляция рендера по формуле C:U даёт габарит `218..863` против `218..865`
   у эталона и размах рук `610 px` против `612 px`; все 17 контрольных строк
   (голова, торс, живот, бёдра, голени, стопы) попадают в ±5 px. T-pose,
   симметрия пар (`cx_R + cx_L = 1500`), чёрная анатомия, обводка по форме и
   ноль белых пикселей на границах спрайтов сохранены. Конвары, мини-игры,
   рука, шрапнель, цвет и контур не правились. Равномерное ×1.15, «~2%» и
   линейная нормализация `101..1401` удалены как ошибочные.
2. **Прежнее правило четырёх точек теперь относится ТОЛЬКО к стеклу.** Старое
   глобальное remapping-правило для дробовика отменено после live-репорта.
   `WSZC.AddShrapnel` вызывает `WSZC.ShrapnelSpawnLimb` только для
   `reason == "glass"`; дробовик/взрыв сохраняют фактический normalized limb
   (`head`, `thorax`, `abdomen`, все arm/forearm/hand и thigh/crus/foot).
   Для стекла получатели по-прежнему только `hand_R`, `hand_L`, `foot_R`,
   `foot_L`. Неразрешённый damage limb не перенаправляется в кисть/стопу.
   За одно попадание ложится **3, 4 или 5 осколков**: стекло/дробовик = 3,
   взрыв добавляет по одному за дополнительный pellet. Верх ограничен
   `ShrapnelPieceCount`.

Чёрный `(0,0,0)`, `EDGE_WIDTH=9`, `EDGE_PAD_MIN=6`, обводка по альфа-форме без
рамок, hover `finalOutline`/`HoverAnims`, мини-игры и `text=all`, рука,
сохранность shrapnel при ragdoll→standing/`RestoreBones`/`ReconcileSpawnShrapnel`,
закрытие по пустому клику, organism/authority, Hemogen и все конвары **не
изменялись**. HUD-панель и оранжевые треугольники с `2-10` не копировались.

Живой GMod агентом не запускался: проверено headless (регрессия, `ALL_LUA_OK`,
пересборка 32 limb PNG + Lua и обоих ZIP), принятие — только по свежим live-скринам.

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
перелом/вывих на один лимб, дробовик — на фактический лимб, стекло — на 4 лимба.

Проверить локально:
`PYTHONPATH=/tmp/pil_pkg python3 tools/fit_unitmenu_geometry.py --reference /path/Screenshot_2-10.png --overlay /tmp/overlay.png`
(жёлтый = совпадение, красный = только эталон, зелёный = только наш рендер).

Suite `82/82` до пересборки архивов, затем полный прогон. Живой GMod не
запускался — принятие по свежему live-скрину.

## №15: повторный live-fix — reset, настоящие дробовики и native WoundView

* **Дробовой путь воспроизведён целиком.** Прежний focused test передавал
  `HITGROUP_RIGHTARM` напрямую и пропускал настоящий resolver. Новые проверки
  вызывают зарегистрированный `PostEntityTakeDamage` с `hitgroup=nil`,
  `took=false`, свежими `org.dmgstack` / `ply.HitBones`, а также идут по пути
  player→FakeRagdoll→обёрнутый `homigrad-damage`. Proxy без владельца больше
  не выставляет `ShrapnelHandled` раньше времени; injection выполнен и внутри
  native-wrapper, поэтому `return true` ZCity не отменяет осколки.
* **Полный reset.** Добавлены source-faithful `H.ResetPlayer → Clear →
  RestoreRagdoll` (последний подавлен), очистка текущего organism, native
  fallback, death-ragdoll и `reset_org`. Пустая shadow-таблица допускается,
  но число фрагментов, раны, infection, dressing/tourniquet и `HitBones`
  после reset равны нулю/пусты. Обычный ragdoll-clear сохраняет их, как и
  прежде. Lua 5.1/5.x wrapper использует `table.unpack or unpack`.
* **Кукла.** `REFERENCE_BOXES` переснят с `Screenshot_1.png` независимо для
  каждой части: native-руки/кисти не принудительно зеркалятся. Чёрный fill и
  shaped white outline сохранены, рамок нет. По 14 частям с надёжной чёрной
  маской IoU checked-in геометрии = **0.9683**; полупрозрачная голова сверена
  по контуру отдельно. Итоговый scale `0.25` вместо `0.24` (+4.17%), hover
  hitboxes используют видимые `hoverW/hoverH`.
* Локальные source-faithful gameplay checks: **37/37**. Живой GMod не
  запускался; это не заменяет live-проверку. Для неизвестных сторонних ошибок
  всё ещё нужен полный клиентский/серверный console stack trace.
