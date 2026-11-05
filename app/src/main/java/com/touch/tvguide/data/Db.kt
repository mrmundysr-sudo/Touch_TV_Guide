package com.touch.tvguide.data

import android.content.Context
import androidx.room.*
import kotlinx.coroutines.flow.Flow

// Feed tables: replaced wholesale on refresh.
@Entity(tableName = "channel")
data class ChannelE(@PrimaryKey val id: String, val name: String, val feedNumber: String?, val logoUrl: String?, val feedCategory: String?)

@Entity(tableName = "program", primaryKeys = ["channelId", "startMillis"], indices = [Index("startMillis")])
data class ProgramE(val channelId: String, val startMillis: Long, val title: String, val description: String?, val stopMillis: Long)

// User tables: never touched by a feed refresh.
@Entity(tableName = "user_number") data class UserNumberE(@PrimaryKey val channelId: String, val number: String)
@Entity(tableName = "user_category") data class UserCategoryE(@PrimaryKey val channelId: String, val category: String)
@Entity(tableName = "fav_channel") data class FavChannelE(@PrimaryKey val channelId: String)
@Entity(tableName = "fav_program") data class FavProgramE(@PrimaryKey val programKey: String)

/** The single Home profile row (id is always 1). Customization lives in the user tables above. */
@Entity(tableName = "home") data class HomeE(@PrimaryKey val id: Int = 1, val zip: String, val providerId: String, val marketId: String)

@Entity(tableName = "meta") data class MetaE(@PrimaryKey val key: String, val value: String)

@Entity(tableName = "reminder")
data class ReminderE(@PrimaryKey val programKey: String, val channelId: String, val channelName: String, val title: String, val startMillis: Long, val stopMillis: Long)

@Dao
interface GuideDao {
    @Query("SELECT * FROM channel") fun observeChannels(): Flow<List<ChannelE>>
    @Query("SELECT * FROM program ORDER BY channelId, startMillis") fun observePrograms(): Flow<List<ProgramE>>
    @Query("SELECT * FROM channel") suspend fun channels(): List<ChannelE>
    @Query("SELECT * FROM program") suspend fun programs(): List<ProgramE>

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertChannels(c: List<ChannelE>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertPrograms(p: List<ProgramE>)
    @Query("DELETE FROM channel") suspend fun clearChannels()
    @Query("DELETE FROM program") suspend fun clearPrograms()

    @Transaction
    suspend fun replaceFeed(channels: List<ChannelE>, programs: List<ProgramE>) {
        clearChannels(); clearPrograms(); insertChannels(channels); insertPrograms(programs)
    }

    // customization
    @Query("SELECT * FROM user_number") fun observeNumbers(): Flow<List<UserNumberE>>
    @Query("SELECT * FROM user_category") fun observeCategories(): Flow<List<UserCategoryE>>
    @Query("SELECT * FROM fav_channel") fun observeFavChannels(): Flow<List<FavChannelE>>
    @Query("SELECT * FROM fav_program") fun observeFavPrograms(): Flow<List<FavProgramE>>
    @Query("SELECT * FROM user_number") suspend fun numbers(): List<UserNumberE>
    @Query("SELECT * FROM user_category") suspend fun categories(): List<UserCategoryE>
    @Query("SELECT * FROM fav_channel") suspend fun favChannels(): List<FavChannelE>
    @Query("SELECT * FROM fav_program") suspend fun favPrograms(): List<FavProgramE>
    @Query("DELETE FROM user_number") suspend fun clearNumbers()
    @Query("DELETE FROM user_category") suspend fun clearCategories()
    @Query("DELETE FROM fav_channel") suspend fun clearFavChannels()
    @Query("DELETE FROM fav_program") suspend fun clearFavPrograms()
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertNumbers(v: List<UserNumberE>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertCategories(v: List<UserCategoryE>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertFavChannels(v: List<FavChannelE>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertFavPrograms(v: List<FavProgramE>)

    @Transaction
    suspend fun replaceCustomization(n: List<UserNumberE>, c: List<UserCategoryE>, fc: List<FavChannelE>, fp: List<FavProgramE>) {
        clearNumbers(); clearCategories(); clearFavChannels(); clearFavPrograms()
        insertNumbers(n); insertCategories(c); insertFavChannels(fc); insertFavPrograms(fp)
    }

    // home + meta
    @Query("SELECT * FROM home WHERE id = 1") fun observeHome(): Flow<HomeE?>
    @Query("SELECT * FROM home WHERE id = 1") suspend fun home(): HomeE?
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun putHome(h: HomeE)
    @Query("SELECT value FROM meta WHERE `key` = :k") suspend fun meta(k: String): String?
    @Query("SELECT value FROM meta WHERE `key` = :k") fun observeMeta(k: String): Flow<String?>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun putMeta(m: MetaE)

    // reminders
    @Query("SELECT * FROM reminder ORDER BY startMillis") fun observeReminders(): Flow<List<ReminderE>>
    @Query("SELECT * FROM reminder ORDER BY startMillis") suspend fun reminders(): List<ReminderE>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun putReminder(r: ReminderE)
    @Query("DELETE FROM reminder WHERE programKey = :key") suspend fun deleteReminder(key: String)
    @Query("DELETE FROM reminder") suspend fun clearReminders()
}

@Database(
    entities = [ChannelE::class, ProgramE::class, UserNumberE::class, UserCategoryE::class, FavChannelE::class,
        FavProgramE::class, HomeE::class, MetaE::class, ReminderE::class],
    version = 1, exportSchema = true,
)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): GuideDao
    companion object {
        fun open(ctx: Context): AppDb = Room.databaseBuilder(ctx.applicationContext, AppDb::class.java, "tvguide.db").build()
    }
}
