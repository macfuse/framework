//
//  NSFileManager.swift
//  macFUSE
//
//  Created by Benjamin Fleischer on 07.10.25.
//

extension FileAttributeKey {
    @_alwaysEmitIntoClient
    public static var flags: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileFlagsKey)
    }

    @_alwaysEmitIntoClient
    public static var accessDate: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileAccessDateKey)
    }

    @_alwaysEmitIntoClient
    public static var changeDate: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileChangeDateKey)
    }

    @_alwaysEmitIntoClient
    public static var backupDate: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileBackupDateKey)
    }

    @_alwaysEmitIntoClient
    public static var sizeInBlocks: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileSizeInBlocksKey)
    }

    @_alwaysEmitIntoClient
    public static var optimalIoSize: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemFileOptimalIOSizeKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsAllocate: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsAllocateKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsCaseSensitiveNames: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsExchangeData: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsExchangeDataKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsSwapRenaming: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsSwapRenamingKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsExclusiveRenaming: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsExclusiveRenamingKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsExtendedDates: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsExtendedDatesKey)
    }

    @_alwaysEmitIntoClient
    public static var systemMaxFilenameLength: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeMaxFilenameLengthKey)
    }

    @_alwaysEmitIntoClient
    public static var systemFileSystemBlockSize: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeFileSystemBlockSizeKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsSetVolumeName: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsSetVolumeNameKey)
    }

    @_alwaysEmitIntoClient
    public static var systemVolumeName: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeNameKey)
    }

    @_alwaysEmitIntoClient
    public static var systemSupportsReadWriteNodeLocking: FileAttributeKey {
        FileAttributeKey(kGMUserFileSystemVolumeSupportsReadWriteNodeLockingKey)
    }
}
