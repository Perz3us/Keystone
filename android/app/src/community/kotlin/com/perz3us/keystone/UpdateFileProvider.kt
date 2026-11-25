// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import androidx.core.content.FileProvider

// Own subclass so it never clashes with a plugin's FileProvider entry.
class UpdateFileProvider : FileProvider()
