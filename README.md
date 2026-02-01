# 🧗‍♂️ Smart Climb NPC System (v1.0 Beta)


![Lua](https://img.shields.io/badge/Lua-Luau-blue?style=for-the-badge&logo=lua)
![Platform](https://img.shields.io/badge/Platform-Roblox-black?style=for-the-badge&logo=roblox)
![Version](https://img.shields.io/badge/Version-1.0_Beta-orange?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**Продвинутая система искусственного интеллекта для Roblox, которая не просто следует за игроком, но и преследует его по вертикали, преодолевая препятствия и адаптируясь к поведению "абузеров".**

---

## ✨ Возможности

* 🧠 **Умное преследование:** Использует `SimplePath` для навигации по земле.
* 🪜 **Вертикальность:** NPC автоматически распознает лестницы (Truss, Ladder parts) и взбирается по ним.
* 🏃 **Паркур:** Механика `Vaulting` (залезания) в конце лестницы — NPC подпрыгивает и закидывает себя на платформу.
* 🛑 **Anti-Cheese System (Expectation):** Уникальная механика, которая наказывает игроков, постоянно прыгающих с лестниц. Если игрок пытается "забайтить" NPC, тот переходит в режим ожидания (кемпинга) у подножия.
* ⚡ **Оптимизация:** Работает на базе событий и таймеров, минимизируя нагрузку (Heartbeat).

---

## 📥 Установка

1.  **Зависимости:** Убедитесь, что у вас установлен модуль [SimplePath](https://github.com/V3N0M-Z/SimplePath) (поместите его в `ReplicatedStorage`).
2.  **Модуль:** Создайте `ModuleScript` с именем `ClimbSystem` в `ReplicatedStorage` и вставьте в него код ядра.
3.  **NPC:** Вам понадобится модель NPC с `Humanoid` и `HumanoidRootPart`.

### Структура папок

```text
game
├── 📂 ReplicatedStorage
│   └── 📂 Modules
│       ├── 📜 SimplePath
│       └── 📜 ClimbSystem (Ваш модуль)
├── 📂 Workspace
│   └── 🤖 NPC_Model
└── 📂 ServerScriptService
    └── 📜 NPC_Controller (Скрипт управления)

⚙️ Конфигурация (CONFIG)
Все настройки находятся в начале скрипта в таблице CONFIG.
🏃 Движение и Физика
| Параметр | По умолч. | Описание |
|---|---|---|
| ClimbSpeed | 14 | Скорость подъема по лестнице. |
| Walk | 16 | Скорость бега по земле. |
| VaultForceForward | 45 | Импульс вперед при залезании на уступ. |
| VaultForceUp | 45 | Импульс вверх при залезании на уступ. |
| JumpBackForce | 30 | Сила отскока от стены при срыве. |
🧠 Логика "Expectation" (Анти-Абуз)
Эта система предотвращает бесконечную беготню вверх-вниз, если игрок прыгает с лестницы.
| Параметр | По умолч. | Описание |
|---|---|---|
| Expectation | false | Вкл/Выкл режим умного ожидания. |
| BailThreshold | 5 | Кол-во спрыгиваний игрока, после которых NPC обидится. |
| BailResetTime | 300 | (сек) Время сброса счетчика прыжков. |
| WaitModeDuration | 300 | (сек) Сколько NPC будет "кемперить" внизу. |
🗺️ Подготовка карты
Чтобы NPC мог лезть, объект должен соответствовать одному из условий:
 * Быть классом TrussPart.
 * Иметь в названии слово "ladder" (регистр не важен).
 * (Рекомендуется) Иметь Tag "ForceClimbable" (используйте CollectionService).
🚀 Использование
Создайте обычный Script (Server) и используйте следующий код для запуска интеллекта:
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ClimbSystem = require(ReplicatedStorage.Modules.ClimbSystem)

local npc = workspace.MyNPC
local isActive = false

-- Простой поиск ближайшего игрока
local function findTarget()
    local closest, target = 100, nil
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") and char.Humanoid.Health > 0 then
            local dist = (char.HumanoidRootPart.Position - npc.HumanoidRootPart.Position).Magnitude
            if dist < closest then
                closest = dist
                target = char
            end
        end
    end
    return target
end

-- Основной цикл
task.spawn(function()
    while npc and npc.Parent do
        local target = findTarget()
        
        -- Запускаем модуль один раз, когда цель найдена
        if target and not isActive then
            isActive = true
            print("🎯 Цель обнаружена, начинаю погоню!")
            ClimbSystem.Start(npc, nil, target)
            break -- Выходим из цикла поиска, модуль теперь управляет NPC
        end
        task.wait(1)
    end
end)

🤖 Как работает режим Expectation
 * NPC преследует игрока на лестнице.
 * Игрок спрыгивает вниз, чтобы убежать.
 * Счетчик BailCount увеличивается.
 * Если игрок делает это слишком часто (больше BailThreshold), NPC включает режим WaitMode.
 * В этом режиме NPC не лезет наверх. Он стоит у основания лестницы и смотрит на игрока, ожидая, пока тот спустится сам или совершит ошибку.
> "NPC: Надоело бегать, подожду тебя внизу."
> 
📝 To-Do / Планы
 * [ ] Добавить систему атаки (Damage) при сближении.
 * [ ] Добавить анимации для карабканья (сейчас процедурная физика).
 * [ ] Звуки шагов и прыжков.
📄 Лицензия
Этот проект распространяется под лицензией MIT. Вы можете свободно использовать и модифицировать код в своих плейсах.

