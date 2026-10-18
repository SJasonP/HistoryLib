package com.sjasonp.historylib

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryLibNavigationTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun topLevelDestinationsOpenTheirPrimaryContent() {
        val activity = composeRule.activity
        val summary = activity.getString(R.string.destination_summary)
        val library = activity.getString(R.string.destination_library)
        val manage = activity.getString(R.string.destination_manage)

        composeRule.onNodeWithText(summary).assertIsDisplayed()
        composeRule.onNodeWithText(library).performClick()
        composeRule.onNodeWithText(activity.getString(R.string.library_search_hint)).assertIsDisplayed()
        composeRule.onNodeWithText(manage).performClick()
        composeRule.onNodeWithText(activity.getString(R.string.manage_import_file)).assertIsDisplayed()
        composeRule.onNodeWithText(activity.getString(R.string.manage_import_folder)).assertIsDisplayed()
    }
}
