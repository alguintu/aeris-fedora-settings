import QtQuick

// The production Home page and its inspector share this one placement map.
DashboardGrid {
    namePrefix: "home"
    placements: [
        {key: "media", name: "MEDIA", column: 0, row: 0, columns: 5, rows: 3, accent: Theme.teal},
        {key: "weather", name: "CLOCK / WEATHER", column: 5, row: 0, columns: 4, rows: 2, accent: Theme.blue},
        {key: "pomodoro", name: "POMODORO", column: 9, row: 0, columns: 4, rows: 2, accent: Theme.mauve},
        {key: "cpu", name: "CPU / RAM", column: 13, row: 0, columns: 5, rows: 2, accent: Theme.cyan},
        {key: "gpu", name: "GPU / VRAM", column: 13, row: 2, columns: 5, rows: 2, accent: Theme.green},
        {key: "awake", name: "AWAKE", column: 5, row: 2, columns: 1, rows: 2, accent: Theme.yellow},
        {key: "storage", name: "STORAGE", column: 6, row: 2, columns: 4, rows: 2, accent: Theme.orange},
        {key: "downloads", name: "DOWNLOADS", column: 10, row: 2, columns: 3, rows: 1, accent: Theme.mauve},
        {key: "network", name: "NETWORK", column: 10, row: 3, columns: 3, rows: 1, accent: Theme.teal},
        {key: "controls", name: "CONTROL RACK", column: 0, row: 3, columns: 5, rows: 1, accent: Theme.teal}
    ]

}
