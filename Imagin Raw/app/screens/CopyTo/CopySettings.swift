//
//  CopySettings.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.08.2026.
//

import Foundation

struct CopySettings {
    let renameByExifDate: Bool
    let useSequentialNumbers: Bool
    let customPrefix: String
    let organizeByYear: Bool
    let organizeByMonth: Bool
    let organizeByDay: Bool
    let eventName: String
    let organizeByCameraModel: Bool
    let organizeJpgsInSubfolder: Bool

    init(_ vm: PhotoCopySheetModel) {
        renameByExifDate        = vm.renameByExifDate
        useSequentialNumbers    = vm.useSequentialNumbers
        customPrefix            = vm.customPrefix
        organizeByYear          = vm.organizeByYear
        organizeByMonth         = vm.organizeByMonth
        organizeByDay           = vm.organizeByDay
        eventName               = vm.eventName
        organizeByCameraModel   = vm.organizeByCameraModel
        organizeJpgsInSubfolder = vm.organizeJpgsInSubfolder
    }
}
