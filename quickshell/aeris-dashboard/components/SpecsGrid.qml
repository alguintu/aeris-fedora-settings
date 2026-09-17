import QtQuick

DashboardGrid {
    namePrefix: "specs"
    placements: [
        {key: "identity", column: 0, row: 0, columns: 3, rows: 4},
        {key: "processor", column: 3, row: 0, columns: 4, rows: 2},
        {key: "graphics", column: 7, row: 0, columns: 4, rows: 2},
        {key: "memory", column: 11, row: 0, columns: 3, rows: 2},
        {key: "chassis", column: 14, row: 0, columns: 4, rows: 2},
        {key: "motherboard", column: 3, row: 2, columns: 4, rows: 2},
        {key: "storage", column: 7, row: 2, columns: 4, rows: 2},
        {key: "system", column: 14, row: 2, columns: 4, rows: 2},
        {key: "fans", column: 11, row: 2, columns: 3, rows: 1},
        {key: "argb", column: 11, row: 3, columns: 3, rows: 1}
    ]
}
