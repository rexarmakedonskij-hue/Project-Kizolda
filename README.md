# Pawductivity — Unity

С 8 октября 2026 года разработка ведётся полностью на Unity.
Активный проект в этом worktree — Unity/, версия редактора — **2022.3.62f1**,
Built-in Render Pipeline. Игровой код написан на C#.

## Запуск

1. Получите исходники и модели через Git LFS: выполните git lfs install и git lfs pull.
2. В Unity Hub добавьте папку Unity/ и откройте её редактором версии из Unity/ProjectSettings/ProjectVersion.txt.
3. Дождитесь импорта и компиляции, откройте Assets/Pawductivity/Scenes/Main.unity и нажмите Play.

Подробности механик и сборки — [Unity/README.md](Unity/README.md).
Инструкция Windows — [WINDOWS_SETUP.md](WINDOWS_SETUP.md).

## Структура

- Unity/ — игровой проект, сцены, C#-скрипты и ресурсы Unity.
- assets/ — общие изображения, модели, Blender-исходники и лицензии. Их наличие не означает, что они уже подключены к Unity.
- AGENTS.md — решения и ограничения проекта.

Проверки прежнего движка удалены и не подтверждают состояние Unity.
Проверки игрового цикла запускаются через **Pawductivity → Validate game rules**.
Сборки создаются локально. Загрузка на Яндекс Диск — только по отдельному запросу.
