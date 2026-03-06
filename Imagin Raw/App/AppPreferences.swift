//
//  AppPreferences.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 04.03.2026.
//

import Foundation
import RCPreferences

enum AppPreference: String, RCPreferencesProtocol {

    // MARK: - Preview
    case alignToTopLeft = "ImageAlignmentTopLeft"

    // MARK: - Sidebar
    case expandedFolders = "ExpandedFolders"
    case selectedFolder = "SelectedFolder"

    // MARK: - Thumbs Grid
    case sortOption = "SelectedSortOption"
    case gridType = "SelectedGridType"

    // MARK: - External App
    case selectedExternalApp = "SelectedExternalApp"

    // MARK: - Folders
    case userFolderBookmarks = "UserManagedFolderBookmarks"

    // MARK: - Copy To
    case copyToRenameByExifDate = "CopyTo_RenameByExifDate"
    case copyToCustomPrefix = "CopyTo_CustomPrefix"
    case copyToOrganizeByYear = "CopyTo_OrganizeByYear"
    case copyToOrganizeByMonth = "CopyTo_OrganizeByMonth"
    case copyToOrganizeByDay = "CopyTo_OrganizeByDay"
    case copyToEventName = "CopyTo_EventName"
    case copyToOrganizeByCameraModel = "CopyTo_OrganizeByCameraModel"
    case copyToOrganizeJpgsInSubfolder = "CopyTo_OrganizeJpgsInSubfolder"
    case copyToLastDestinationURL = "CopyTo_LastDestinationURL"
    case copyToLastBackupDestinationURL = "CopyTo_LastBackupDestinationURL"
    case copyToDestinationBookmark = "CopyTo_DestinationBookmark"
    case copyToBackupBookmark = "CopyTo_BackupBookmark"

    func defaultValue() -> Any {
        switch self {
        case .alignToTopLeft:           return false
        case .expandedFolders:          return Data()
        case .selectedFolder:           return Data()
        case .sortOption:               return "name"
        case .gridType:                 return "threeColumns"
        case .selectedExternalApp:      return ""
        case .userFolderBookmarks:      return Data()
        case .copyToRenameByExifDate:   return false
        case .copyToCustomPrefix:       return ""
        case .copyToOrganizeByYear:     return false
        case .copyToOrganizeByMonth:    return false
        case .copyToOrganizeByDay:      return false
        case .copyToEventName:          return ""
        case .copyToOrganizeByCameraModel: return false
        case .copyToOrganizeJpgsInSubfolder: return false
        case .copyToLastDestinationURL: return ""
        case .copyToLastBackupDestinationURL: return ""
        case .copyToDestinationBookmark: return Data()
        case .copyToBackupBookmark:     return Data()
        }
    }
}

let appPrefs = RCPreferences<AppPreference>()
