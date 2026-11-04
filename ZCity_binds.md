# ZCity: все клавиши, бинды и команды

Шпаргалка составлена по статическому разбору `zcity.zip` (888 Lua-файлов),
`casualites unknown.zip` и `woundsystem_zcity_compat/`. Живой GMod не
запускался: это «что написано в коде», а не «проверено на сервере».

**Главное:** ZCity почти не создаёт собственных биндов. Он перехватывает
стандартные команды GMod (`+use`, `+menu`, `+attack`, `slot1`, …) через
`PlayerBindPress` / `CUserCommand`, плюс читает **физические клавиши** напрямую
через `input.IsKeyDown(KEY_*)` и `PlayerButtonDown`. Вторую группу **нельзя
переназначить консольной командой `bind`** — сработает именно та клавиша, что
зашита в коде.

Пути ниже — относительно папки аддона `z_city/`.

---

## 1. Обязательный минимум (стандартные бинды GMod)

Дефолты GMod: `q +menu`, `c +menu_context`, `e +use`, `r +reload`,
`MOUSE1 +attack`, `MOUSE2 +attack2`, `MWHEELUP invprev`,
`MWHEELDOWN invnext`, `1..9 slot1..9`, `ALT +walk`, `CTRL +duck`,
`SHIFT +speed`, `SPACE +jump`, `y messagemode`, `u messagemode2`,
`f impulse 100`, `TAB +showscores`, `x +voicerecord`, `v noclip`.
Список подтверждается стандартным `config.cfg` [3](https://steamcommunity.com/app/4000/discussions/1/619568793942398382/?l=french).

| Клавиша | Команда | Что делает именно в ZCity | Источник |
|---|---|---|---|
| `W A S D` | `+forward` / `+moveleft` / `+back` / `+moveright` | Движение; в ragdoll-режиме — управление телом | `lua/homigrad/fake/sv_control.lua:320` |
| `SPACE` | `+jump` | Прыжок; подъём/движение в ragdoll | `lua/homigrad/fake/sv_control.lua:224` |
| `CTRL` | `+duck` | Присесть; в машине Glide — смена камеры 1/3 лицо | `lua/glide/client/camera.lua:242` |
| `SHIFT` | `+speed` | Бег; `SHIFT + E` — быстрее открыть дверь | `lua/initpost/sh_initpost.lua:330` |
| `ALT` | `+walk` | Медленный шаг; `ALT + E` — медленно открыть дверь; удержание `LAlt` = шепот в чате | `lua/initpost/sh_initpost.lua:329`, `lua/homigrad/cl_chat.lua:80` |
| `E` | `+use` | Поднять предмет/оружие, открыть дверь, обыск тела, лестницы, ладдер | `lua/weapons/homigrad_base/shared.lua:139`, `lua/initpost/sh_initpost.lua:328` |
| `R` | `+reload` | Перезарядка; смена режима медицины/огнестрела; `R + ЛКМ` — смена режима атаки ножа; закрыть окно обыска (`KEY_R`) | `lua/weapons/weapon_hg_medicine_base.lua:278`, `lua/weapons/weapon_sogknife.lua:4`, `lua/homigrad/sh_inventory.lua:161` |
| `ЛКМ` | `+attack` | Атака / применить предмет на себе / подтвердить выбор в круговом меню | `lua/homigrad/cl_hud.lua:487`, `lua/homigrad/cl_utility.lua:88` |
| `ПКМ` | `+attack2` | Прицеливание, блок, бросок, применить предмет **на другом** игроке; альтернативный пункт радиал-меню | `lua/weapons/weapon_needle.lua:4`, `lua/homigrad/cl_hud.lua:504` |
| `Колесо вверх/вниз` | `invprev` / `invnext` | Селектор оружия ZCity; на оптике — подстройка прицела | `lua/homigrad/hud/cl_weapon_selector.lua:246`, `lua/weapons/homigrad_base/cl_optics.lua:12` |
| `1 2 3 4 5 6` | `slot1` … `slot6` | Слоты селектора оружия ZCity (не ванильный HUD) | `lua/homigrad/hud/cl_weapon_selector.lua:142` |
| `Q` | `+menu` | **Перехвачено:** круговое меню (radial). Не спавн-меню! | `lua/homigrad/cl_hud.lua:439` |
| `C` | `+menu_context` | Context-меню. Не-админам ZCity его блокирует; в sandbox `KEY_C` используется радиал-меню | `lua/homigrad/cl_hud.lua:453`, `:471` |
| `lastinv` | `lastinv` | Прошлое оружие в селекторе ZCity (клавишу задайте сами) | `lua/homigrad/hud/cl_weapon_selector.lua:259` |
| `Y` / `U` | `messagemode` / `messagemode2` | `messagemode` перехватывается чатом ZChat; ванильный `CHudChat` скрыт | `lua/homigrad/zchat/sh_chat.lua:34` |
| `LAlt` (удержание) | — | Шепот в ZChat (`ChatWhisper`) | `lua/homigrad/cl_chat.lua:80` |
| `F` | `impulse 100` | Фонарик; если у оружия есть underbarrel — переключение ЛЦУ/подствольного фонаря | `lua/weapons/homigrad_base/sh_attachment.lua:402` |
| `TAB` | `+showscores` | Скорборд (стандарт GMod) | — |
| `V` | `noclip` | Только админам: `PlayerNoClip` запрещает вход всем остальным | `gamemodes/zcity/gamemode/shared.lua:51` |
| `F1 F2 F3 F4` | `gm_showhelp` / `gm_showteam` / `gm_showspare1` / `gm_showspare2` | Стандарт GMod; `F4` дополнительно занят панелью предателя | `gamemodes/zcity/gamemode/modes/homicide/cl_hud.lua:235` |
| `F5` / `F6` / `F9` | `jpeg` / `save quick` / `load quick` | `F6` дополнительно занят админ-меню ZCity | `gamemodes/zcity/gamemode/libraries/cl_modeselect_menu.lua:615` |

### Как работает круговое меню

Нажатие `+menu` (`Q`) → `CreateRadialMenu()`; отпускание → `PressRadialMenu(1)`.
Пока меню открыто, **ЛКМ** выбирает пункт, **ПКМ** — альтернативное действие
пункта (второй аргумент `mouseClick`); курсор ставится в центр экрана.
При `otrub` (бессознательном состоянии) меню принудительно закрывается.
Источник: `lua/homigrad/cl_hud.lua:209-268, 391-458, 460-520`.

Пункты меню собираются хуком `radialOptions`: фразы, снаряжение/броня,
меню патронов, перезарядка с пола, сошки, вправление вывихов (radial `hg_fixdislocation`
остаётся ванильным; дополнительно из WoundView доступна ручная мини-игра
`FIX DISLOCATION`), ПНО,
«Examine Body» (заменён компат-аддоном на «Проверить травмы»), крафт инженера,
запрос поддержки/авиаудара, скан фурри, змейка и т.д.

Мини-игра `FIX DISLOCATION` из WoundView — родная C:U, но компат уменьшает её
клип (`zc_woundsystem_compat_native_minigame_zoom`, по умолчанию `0.75`) и
стартовое смещение кости (`zc_woundsystem_compat_dislocation_start`, по
умолчанию `35`), чтобы кость была на экране и нажималась. Размер спрайта руки
в мини-играх бинта/шприца — `zc_woundsystem_compat_hand_cursor_scale`.

**После смерти:** LMB по экрану отправляет `WoundSystem_PlayerRespawnRequest`
(обработчик живёт в хуке `WoundSystem_DeathScreenDisplay` из C:U; компат гасит
только его отрисовку, но не ввод). Запрос обрабатывается серверным
`sv_deathscreen.lua`, который до этого блокирует обычный респавн хуком
`WoundSystem_BlockRespawn`. Задержка — 1 секунда от смерти.

---

## 2. «Зашитые» клавиши — биндом не меняются

Это `KEY_*` константы, читаемые напрямую. Если клавиша не нажата физически,
действие не сработает, даже если вы привязали команду к другой кнопке.

| Клавиша | Действие | Условие / режим | Источник |
|---|---|---|---|
| `Q` (не-sandbox) / `C` (sandbox) | Удержание радиал-меню | `engine.ActiveGamemode()` | `lua/homigrad/cl_hud.lua:471` |
| `1` | Радиальный инвентарь: зажать → выбрать оружие, отпустить → подтвердить | `GetGlobalBool("RadialInventory") == true` | `lua/homigrad/new_inventory/cl_inventory.lua:3-30` |
| `R` | Закрыть окно обыска | Окно открыто | `lua/homigrad/sh_inventory.lua:161` |
| `F` | Меню «вины»/кармы `hg_guilt_menu` | Не в меню паузы, нет фокуса ввода | `gamemodes/zcity/gamemode/libraries/guilt/cl_guilt.lua:89` |
| `F` | Способность класса Combine | `sh_combine.lua` | `lua/homigrad/playerclass/classes/sh_combine.lua:925` |
| `F6` | Админ-меню выбора режима | Только `IsAdmin()` | `gamemodes/zcity/gamemode/libraries/cl_modeselect_menu.lua:615` |
| `F4` | Панель предателя (traitor panel) | Homicide, только предатель | `gamemodes/zcity/gamemode/modes/homicide/cl_hud.lua:235` |
| `E` | RTS-вселение в наблюдаемого | Coop, `coop_rts`, игрок мёртв | `gamemodes/zcity/gamemode/modes/coop/sv_coop.lua:615` |
| `W A S D R` | Змейка (мини-игра в `cl_init.lua`) | Пасхалка | `gamemodes/zcity/gamemode/cl_init.lua:1079-1087` |
| `S T A U ENTER SPACE ; BACKSPACE` | Печать «статуса» в раунде `fear` | Раунд fear, последний живой | `lua/homigrad/cl_utility.lua:152-190` |
| `MOUSE_LEFT` / `MOUSE_RIGHT` | Выбор в радиал-меню, 3D2D-интерфейсы, обезвреживание бомбы | — | `lua/homigrad/cl_hud.lua:487`, `lua/homigrad/libraries/cl_3d2dvgui.lua:165` |
| `MOUSE_WHEEL_UP/DOWN` | Прокрутка в меню Homicide, подстройка оптики | — | `gamemodes/zcity/gamemode/modes/homicide/cl_derma.lua:229` |
| `ESCAPE` | Отмена/выход из мини-игр C:U | Мини-игра открыта | `woundsystem_zcity_compat/lua/autorun/client/wszc_cl_bandage.lua:137` |
| `IN_ZOOM` (`+zoom`) | Зум камеры в машине Glide | В транспорте | `lua/glide/client/camera.lua:220` |
| `IN_ALT1` / `IN_ALT2` (`+alt1`/`+alt2`) | Наклон/положение рук в анимациях | — | `lua/weapons/homigrad_base/sh_anim.lua:354` |

**Блокировки:** в конце раунда CriResp `PlayerBindPress` глушит `+menu`,
`+use`, `+attack` (`gamemodes/zcity/gamemode/modes/criresp/cl_criresp.lua:1118`),
а `StartCommand` снимает почти все `IN_*` (`:1106-1115`). В TDM / DM /
SFD / ScugArena на старте раунда снимается `IN_ATTACK`, `IN_ATTACK2` и движение.
`SpawnMenuOpen` запрещает спавн-меню всем, кроме админов
(`gamemodes/zcity/gamemode/shared.lua:68`).

---

## 3. Оружие и предметы (комбинации)

| Комбинация | Действие | Источник |
|---|---|---|
| `ЛКМ` | Удар/выстрел, применить лекарство на себе | `lua/weapons/weapon_needle.lua:4` |
| `ПКМ` | Прицел / блок / бросок (`RMB + LMB`), укол другому, обезболивающее другому, морфин/налоксон другому | `lua/weapons/weapon_brick.lua:4`, `lua/weapons/weapon_morphine.lua:4` |
| `R` | Перезарядка, смена режима медицины/огнестрела, смена типа патронов | `lua/weapons/weapon_hg_medicine_base.lua:278` |
| `R + ЛКМ` | Сменить режим атаки ножа | `lua/weapons/weapon_sogknife.lua:4` |
| `ALT + E` / `SHIFT + E` | Медленно / быстро открыть дверь | `lua/initpost/sh_initpost.lua:328-335` |
| `E` (удержание) | Поднять предмет, обыск, лестница | `lua/initpost/sh_initpost.lua:328` |
| `SHIFT + ALT` с руками | Специальная анимация (инерция) | `lua/homigrad/cl_utility.lua:536` |
| `CTRL` | Присесть; `CTRL + ЛКМ` — добивание/curbstomp в legkick | `lua/homigrad/dynamic_anims_util/animations/legkick/sv_legkick.lua:24` |
| `ЛКМ` / `ПКМ` / `ESC` во время мини-игры | Работа с бинтом, шприцем, шрапнелью, АНД, вывихом | `woundsystem_zcity_compat/lua/autorun/client/wszc_cl_*.lua` |

Подсказки предметов (`HowToUseInstructions`) берут клавишу из
`input.LookupBinding("+use")`; если `+use` не привязан, в HUD появится
`BIND YOUR +USE KEY PLEASE. WRITE "bind e +use" IN CONSOLE...`
(`lua/weapons/homigrad_base/shared.lua:139`). Аналогично для `+walk` и
`+speed` в подсказках дверей (`lua/initpost/sh_initpost.lua:328-330`).

---

## 4. Режимные и ролевые клавиши

| Режим | Клавиша | Действие |
|---|---|---|
| Homicide | `F4` | Панель предателя |
| Homicide / Defense / HL2DM | радиал `Q` | Крафт инженера, запрос поддержки, заказ supplies, авиаудар |
| Coop | `E` | Вселиться в наблюдаемого (RTS), будучи мёртвым |
| Coop / Homicide | `ALT + E`, `E`, `SHIFT` | Способности подролей/профессий (`IN_WALK + IN_USE`, `IN_SPEED`, `IN_RELOAD`) |
| Любой | `F` | Меню вины/кармы |
| Админ | `F6` | Меню выбора режима раунда |
| Sandbox | `C` | Радиал-меню (вместо `Q`) |

---

## 5. Транспорт Glide (настраивается в Options → Glide, сохраняется в `glide.json`)

Дефолты из `lua/glide/sh_input.lua:74-124`. Это **не** консольные бинды:
переназначаются в меню настроек Glide.

### Общие

| Клавиша | Действие |
|---|---|
| `ЛКМ` | Атака / оружие |
| `R` | Сменить оружие |
| `I` | Завести/заглушить двигатель |
| `H` | Фары |
| `LAlt` | Свободный обзор (free look) |
| `1 … 9 0` | Переключение сидений (`glide_switch_seat`) |
| `CTRL` (`IN_DUCK`) | Сменить камеру 1-е / 3-е лицо |
| `+zoom` (`IN_ZOOM`) | Приблизить камеру |
| `ALT` (`IN_WALK`) | При посадке — сесть в ближайшее сиденье |

### Наземный транспорт

| Клавиша | Действие |
|---|---|
| `W` / `S` | Газ / тормоз |
| `A` / `D` | Руль влево / вправо |
| `SPACE` | Ручник |
| `LSHIFT` | Модификатор газа |
| `R` | Гудок |
| `L` | Сирена |
| `K` | Отцепить прицеп |
| `↑` / `↓` | Наклон вперёд / назад |
| `←` / `→` | Поворотник левый / правый |
| `F` / `J` / `M` | Повысить / понизить передачу / нейтраль |

### Авиация

| Клавиша | Действие |
|---|---|
| `W` / `S` | Тяга больше / меньше |
| `A` / `D` | Рыскание влево / вправо |
| `↑` / `↓` | Тангаж вниз / вверх |
| `←` / `→` | Крен влево / вправо |
| `SPACE` | Альтернативная атака |
| `G` | Шасси |
| `F` | Ловушки/contre-mesures |

Glide блокирует конфликтующие бинды через `PlayerBindPress` (`Glide.BlockBinds`),
но **не** блокирует `+use`, `+reload`, `+attack`, `+attack2`, `+attack3`, `+walk`
(`lua/glide/client/events.lua:53-66`).

---

## 6. Casualties: Unknown и компат-аддон

Настраиваются конварами C:U в меню Options (Q → Options → Casualties/WoundSystem):

| Клавиша | Конвар | Действие |
|---|---|---|
| `T` | `woundsys_woundview_key` (по умолчанию `KEY_T`) | Открыть/закрыть панель осмотра ран WoundView |
| `F` | `woundsys_bodyuse_key` (по умолчанию `KEY_F`) | Взять «body-use» медпредмет, сидя на корточках |
| `E` | `woundsys_worlditem_grab_key` (по умолчанию `KEY_E`) | Поднять мировой медпредмет; при `KEY_E` C:U глушит `+use` |
| `ЛКМ` / `ПКМ` / `СКМ` | — | Клики в панели и в мини-играх |
| `ESC` | — | Закрыть мини-игру |

Источник: `casualties_unknown_health_system_beta/lua/woundsystem/client/cl_options.lua:48-54`,
`cl_health_gui.lua:2242, 2356, 3810, 5230`.

Команды, которые удобно повесить на свободную клавишу:

```text
woundsys_open_panel          // открыть панель C:U
wszc_open_wounds             // то же, но с gate WSZC_Ready (компат-аддон)
```

В круговом меню ZCity (`Q`) компат-аддон заменяет «Examine Body» пунктом
**«Проверить травмы»** → та же родная панель C:U, self-only.

---

## 7. Команды без дефолтного бинда (назначьте сами)

Все они зарегистрированы в ZCity через `concommand.Add`:

```text
drop / dropweapon / -drop / -dropweapon   бросить оружие/предмет (+drop не регистрируется)
+hg_zoom / -hg_zoom / hg_zoom             зум «от плеча» (toggle)
+altlook / -altlook                       альтернативный обзор
+hmcd_holdbreath / -hmcd_holdbreath       задержать дыхание
hg_inspect                               осмотр оружия
hg_options                               меню настроек ZCity
hg_appearance_menu                       редактор внешности
hg_ammomenu                              меню патронов
hg_phrase / hg_phrase_context             фразы персонажа
hg_guilt_menu                            меню вины/кармы (по умолчанию F)
hg_change_posture / hg_change_standposture
hg_place_bipod / hg_reloadfloorweapon / hg_unload_ammo / hg_rolldrum
hg_drop_equipment / hg_dropflashlight / hg_dropsling / hg_dropkastet
hg_enable_nvg / hg_hand_gesture / hg_walkietalkie_adjust / hg_show_weapons
hg_weaponsettings / hg_pointshop / hg_achievements / hg_timer / hg_gopro
glide_switch_seat <1-10>                 смена сиденья в транспорте
```

Пример назначения (положите в `garrysmod/cfg/autoexec.cfg`):

```text
bind "g" "dropweapon"
bind "mouse4" "+hg_zoom"
bind "mouse5" "lastinv"
bind "kp_enter" "woundsys_open_panel"
```

---

## 8. Конфликты, из-за которых бывают «еррорки» и странности

| Клавиша | Кто её использует одновременно |
|---|---|
| `Q` | GMod `+menu` (spawn menu) ↔ **ZCity radial** ↔ `lastinv` в селекторе |
| `C` | GMod `+menu_context` ↔ радиал в sandbox ↔ заблокировано не-админам |
| `F` | `impulse 100` (фонарик/ЛЦУ) ↔ `hg_guilt_menu` ↔ класс Combine ↔ C:U `bodyuse` ↔ Glide `shift_up`/`countermeasures` |
| `E` | `+use` ↔ C:U grab медпредмета ↔ Coop RTS-вселение |
| `R` | `+reload` ↔ закрытие окна обыска ↔ режим ножа ↔ Glide horn / switch_weapon |
| `F4` | `gm_showspare2` ↔ панель предателя |
| `F6` | `save quick` ↔ админ-меню раундов |
| `1` | `slot1` ↔ радиальный инвентарь (при `RadialInventory`) |
| `Колесо` | `invnext/invprev` ↔ зум оптики ↔ прокрутка меню Homicide |
| `ALT` | `+walk` ↔ шепот ↔ Glide free look ↔ посадка в ближайшее сиденье |
| `T` | C:U WoundView ↔ всё, что вы туда привяжете |

Если что-то «не нажимается», сначала проверьте `bind <клавиша>` в консоли и
`input.LookupBinding("+use")`; большая часть подсказок ZCity строится именно из
этих трёх биндов: `+use`, `+walk`, `+speed`.

---

## 9. Готовый конфиг

Файл `zcity_binds.cfg` в корне репозитория содержит все обязательные бинды
одним блоком. Скопируйте его в `garrysmod/cfg/` и выполните в консоли
`exec zcity_binds.cfg`, либо вставьте содержимое в `autoexec.cfg`.
Он **не трогает** зашитые `KEY_*` клавиши и не назначает спорные `F`/`F4`/`F6`
на что-то новое — только фиксирует стандарт GMod, который ожидает ZCity.
