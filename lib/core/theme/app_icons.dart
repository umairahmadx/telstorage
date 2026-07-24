import 'package:flutter/material.dart';

/// Central icon registry for the app.
/// All screens must reference these constants - no hardcoded [Icons.xxx] allowed.
abstract final class AppIcons {
  // -- Actions --------------------------------------------------------------
  static const IconData share         = Icons.ios_share_rounded;
  static const IconData copyLink      = Icons.copy_rounded;
  static const IconData download      = Icons.download_rounded;
  static const IconData upload        = Icons.cloud_upload_outlined;
  static const IconData delete        = Icons.delete_outline_rounded;
  static const IconData move          = Icons.drive_file_move_rounded;
  static const IconData rename        = Icons.edit_rounded;
  static const IconData add           = Icons.add_rounded;
  static const IconData newFolder     = Icons.create_new_folder_rounded;
  static const IconData search        = Icons.search_rounded;
  static const IconData searchOff     = Icons.search_off_rounded;
  static const IconData more          = Icons.more_horiz_rounded;
  static const IconData close         = Icons.close_rounded;
  static const IconData back          = Icons.arrow_back_rounded;
  static const IconData chevronRight  = Icons.chevron_right_rounded;
  static const IconData sortAsc       = Icons.arrow_upward_rounded;
  static const IconData sortDesc      = Icons.arrow_downward_rounded;
  static const IconData pause         = Icons.pause_rounded;
  static const IconData play          = Icons.play_arrow_rounded;
  static const IconData selectAll     = Icons.select_all_rounded;
  static const IconData filterOff     = Icons.filter_alt_off_rounded;
  static const IconData logout        = Icons.logout_rounded;

  // -- File types ------------------------------------------------------------
  static const IconData fileGeneric   = Icons.insert_drive_file_rounded;
  static const IconData fileImage     = Icons.image_rounded;
  static const IconData fileVideo     = Icons.play_circle_fill_rounded;
  static const IconData filePdf       = Icons.picture_as_pdf_rounded;
  static const IconData fileArchive   = Icons.folder_zip_rounded;
  static const IconData filePalette   = Icons.palette_outlined;
  static const IconData folder        = Icons.folder_rounded;
  static const IconData folderOpen    = Icons.folder_open_rounded;
  static const IconData link          = Icons.link_rounded;

  // -- Navigation ------------------------------------------------------------
  static const IconData navHome           = Icons.home_filled;
  static const IconData navHomeOutlined   = Icons.home_outlined;
  static const IconData navFiles          = Icons.folder_outlined;
  static const IconData navTransfer       = Icons.sync_alt_rounded;
  static const IconData navSettings       = Icons.settings_outlined;
  static const IconData navDownloads      = Icons.download_rounded;
  static const IconData navUploads        = Icons.cloud_upload_outlined;
  static const IconData navShared         = Icons.ios_share_rounded;
  static const IconData menu              = Icons.menu_rounded;

  // -- Cloud / sync ----------------------------------------------------------
  static const IconData cloudUpload   = Icons.cloud_upload_outlined;
  static const IconData cloudQueue    = Icons.cloud_queue_rounded;
  static const IconData cloudDone     = Icons.cloud_done_rounded;
  static const IconData syncing       = Icons.sync_rounded;

  // -- Status ----------------------------------------------------------------
  static const IconData statusDone    = Icons.check_circle_rounded;
  static const IconData statusError   = Icons.error_rounded;
  static const IconData statusPending = Icons.schedule_rounded;
  static const IconData statusPublic  = Icons.public_rounded;
  static const IconData selectionOn   = Icons.check_circle_rounded;
  static const IconData selectionOff  = Icons.radio_button_unchecked_rounded;

  // -- Settings / account ----------------------------------------------------
  static const IconData info          = Icons.info_outline_rounded;
  static const IconData theme         = Icons.contrast_rounded;
  static const IconData storage       = Icons.offline_bolt_rounded;
  static const IconData security      = Icons.shield_rounded;
  static const IconData lock          = Icons.lock_outline_rounded;
  static const IconData visibilityOn  = Icons.visibility_outlined;
  static const IconData visibilityOff = Icons.visibility_off_outlined;
  static const IconData email         = Icons.email_outlined;
  static const IconData key           = Icons.key_rounded;
  static const IconData tag           = Icons.tag_rounded;
  static const IconData qrCode        = Icons.qr_code_2_rounded;
  static const IconData calendar      = Icons.calendar_today_outlined;
  static const IconData dropdownArrow = Icons.keyboard_arrow_down_rounded;
  static const IconData uploadFile    = Icons.upload_file_rounded;
}
