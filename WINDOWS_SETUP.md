# Pawductivity — запуск Unity на Windows

1. Установите Git и Git LFS, получите репозиторий и выполните git lfs pull.
2. Установите Unity Hub и редактор **2022.3.62f1** — версия указана в Unity/ProjectSettings/ProjectVersion.txt.
3. Для Windows-сборок добавьте модуль Windows Build Support.
4. В Unity Hub выберите Add project from disk и укажите папку Unity/.
5. Дождитесь импорта и компиляции скриптов.
6. Откройте Assets/Pawductivity/Scenes/Main.unity и нажмите Play.

Комната, кот и интерфейс создаются при запуске; до Play сцена содержит объект Pawductivity.

## Проверка и сборка

- **Pawductivity → Validate game rules** — встроенные проверки правил игры.
- **Pawductivity → Build Windows** — проверка правил и сборка в Unity/Builds/Windows/Pawductivity.exe.

Сборку и визуальное качество проверяйте в Unity и в готовом приложении.
Общие Blender-исходники находятся в assets/; автоматически в игру они не подключены.
При использовании стороннего кота сохраняйте его атрибуцию и лицензию.
Готовые сборки хранятся локально; загрузка на Яндекс Диск требует отдельного запроса.
