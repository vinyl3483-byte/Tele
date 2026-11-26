package com.telefam.company.app.data.local

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "conversations")
data class ConversationEntity(
    @PrimaryKey val id: String,
    val titleEncrypted: String,
    val updatedAtMs: Long
)

@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey val id: String,
    val conversationId: String,
    val senderId: String,
    val clientMutationId: String,
    val bodyEncrypted: String,
    val createdAtMs: Long,
    val isPendingSync: Boolean
)

@Entity(tableName = "outbox_mutations")
data class OutboxMutationEntity(
    @PrimaryKey val mutationId: String,
    val actionType: String,
    val payloadEncrypted: String,
    val createdAtMs: Long,
    val attemptCount: Int
)

@Entity(tableName = "cooldown_records")
data class CooldownEntity(
    @PrimaryKey val emailHash: String,
    val resendCount: Int,
    val blockedUntilSec: Long,
    val lastSentAtSec: Long
)

@Entity(tableName = "encrypted_kv")
data class EncryptedKvEntity(
    @PrimaryKey val key: String,
    val valueEncrypted: String
)

@Entity(tableName = "cached_contacts")
data class CachedContactEntity(
    @PrimaryKey val userId: String,
    val fullNameEncrypted: String,
    val usernameEncrypted: String,
    val locationEncrypted: String,
    val avatarFingerprintHash: String,
    val isFollowing: Boolean,
    val followsMe: Boolean,
    val riskScore: Int,
    val updatedOrder: Long
)

@Entity(tableName = "queued_posts")
data class QueuedPostEntity(
    @PrimaryKey val queueId: String,
    val postType: String,
    val payloadEncrypted: String,
    val createdAtMs: Long,
    val attemptCount: Int
)

@Entity(tableName = "cached_feed_videos")
data class CachedFeedVideoEntity(
    @PrimaryKey val cacheKey: String,
    val feedTab: String,
    val videoId: String,
    val sortOrder: Int,
    val payloadEncrypted: String,
    val cachedAtMs: Long
)

@Dao
interface TelefamDao {
    @Query("SELECT * FROM conversations ORDER BY updatedAtMs DESC")
    fun observeConversations(): Flow<List<ConversationEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertConversations(items: List<ConversationEntity>)

    @Query("DELETE FROM conversations")
    suspend fun clearConversations()

    @Query("SELECT * FROM messages WHERE conversationId = :conversationId ORDER BY createdAtMs ASC")
    fun observeMessages(conversationId: String): Flow<List<MessageEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMessages(items: List<MessageEntity>)

    @Query("UPDATE messages SET isPendingSync = 0 WHERE clientMutationId IN (:mutationIds)")
    suspend fun markMessagesSynced(mutationIds: List<String>)

    @Query("DELETE FROM messages WHERE id = :messageId")
    suspend fun deleteMessageById(messageId: String)

    @Query("DELETE FROM messages")
    suspend fun clearMessages()

    @Query("SELECT * FROM outbox_mutations ORDER BY createdAtMs ASC LIMIT :limit")
    suspend fun peekOutbox(limit: Int): List<OutboxMutationEntity>

    @Query("SELECT COUNT(*) FROM outbox_mutations")
    fun observePendingCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun enqueueOutbox(item: OutboxMutationEntity)

    @Query("DELETE FROM outbox_mutations WHERE mutationId IN (:ids)")
    suspend fun ackOutbox(ids: List<String>)

    @Query("UPDATE outbox_mutations SET attemptCount = attemptCount + 1 WHERE mutationId IN (:ids)")
    suspend fun incrementOutboxAttempts(ids: List<String>)

    @Query("DELETE FROM outbox_mutations")
    suspend fun clearOutbox()

    @Query("SELECT * FROM cooldown_records WHERE emailHash = :emailHash LIMIT 1")
    suspend fun getCooldown(emailHash: String): CooldownEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCooldown(entity: CooldownEntity)

    @Query("DELETE FROM cooldown_records WHERE emailHash = :emailHash")
    suspend fun deleteCooldown(emailHash: String)

    @Query("SELECT valueEncrypted FROM encrypted_kv WHERE `key` = :key LIMIT 1")
    suspend fun getKv(key: String): String?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun putKv(entity: EncryptedKvEntity)

    @Query("DELETE FROM encrypted_kv WHERE `key` = :key")
    suspend fun deleteKv(key: String)

    @Query("SELECT * FROM cached_contacts ORDER BY updatedOrder ASC")
    fun observeCachedContacts(): Flow<List<CachedContactEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCachedContacts(items: List<CachedContactEntity>)

    @Query("UPDATE cached_contacts SET isFollowing = :isFollowing WHERE userId = :userId")
    suspend fun updateContactFollowing(userId: String, isFollowing: Boolean)

    @Query("DELETE FROM cached_contacts")
    suspend fun clearCachedContacts()

    @Query("SELECT * FROM queued_posts ORDER BY createdAtMs ASC")
    suspend fun listQueuedPosts(): List<QueuedPostEntity>

    @Query("SELECT COUNT(*) FROM queued_posts")
    fun observeQueuedPostsCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertQueuedPost(item: QueuedPostEntity)

    @Query("UPDATE queued_posts SET attemptCount = attemptCount + 1 WHERE queueId = :queueId")
    suspend fun incrementQueuedPostAttempts(queueId: String)

    @Query("DELETE FROM queued_posts WHERE queueId = :queueId")
    suspend fun deleteQueuedPost(queueId: String)

    @Query("DELETE FROM queued_posts")
    suspend fun clearQueuedPosts()

    @Query("SELECT * FROM cached_feed_videos WHERE feedTab = :feedTab ORDER BY sortOrder ASC")
    suspend fun getCachedFeedVideos(feedTab: String): List<CachedFeedVideoEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCachedFeedVideos(items: List<CachedFeedVideoEntity>)

    @Query("DELETE FROM cached_feed_videos WHERE feedTab = :feedTab")
    suspend fun clearCachedFeedVideosByTab(feedTab: String)

    @Query("DELETE FROM cached_feed_videos WHERE videoId = :videoId")
    suspend fun deleteCachedFeedVideo(videoId: String)

    @Query("DELETE FROM cached_feed_videos")
    suspend fun clearAllCachedFeedVideos()
}

@Database(
    entities = [
        ConversationEntity::class,
        MessageEntity::class,
        OutboxMutationEntity::class,
        CooldownEntity::class,
        EncryptedKvEntity::class,
        CachedContactEntity::class,
        QueuedPostEntity::class,
        CachedFeedVideoEntity::class
    ],
    version = 4,
    exportSchema = false
)
abstract class TelefamDatabase : RoomDatabase() {
    abstract fun dao(): TelefamDao

    companion object {
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `cached_contacts` (
                        `userId` TEXT NOT NULL,
                        `fullNameEncrypted` TEXT NOT NULL,
                        `usernameEncrypted` TEXT NOT NULL,
                        `locationEncrypted` TEXT NOT NULL,
                        `avatarFingerprintHash` TEXT NOT NULL,
                        `isFollowing` INTEGER NOT NULL,
                        `followsMe` INTEGER NOT NULL,
                        `riskScore` INTEGER NOT NULL,
                        `updatedOrder` INTEGER NOT NULL,
                        PRIMARY KEY(`userId`)
                    )
                    """.trimIndent()
                )
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `queued_posts` (
                        `queueId` TEXT NOT NULL,
                        `postType` TEXT NOT NULL,
                        `payloadEncrypted` TEXT NOT NULL,
                        `createdAtMs` INTEGER NOT NULL,
                        `attemptCount` INTEGER NOT NULL,
                        PRIMARY KEY(`queueId`)
                    )
                    """.trimIndent()
                )
            }
        }

        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `cached_feed_videos` (
                        `cacheKey` TEXT NOT NULL,
                        `feedTab` TEXT NOT NULL,
                        `videoId` TEXT NOT NULL,
                        `sortOrder` INTEGER NOT NULL,
                        `payloadEncrypted` TEXT NOT NULL,
                        `cachedAtMs` INTEGER NOT NULL,
                        PRIMARY KEY(`cacheKey`)
                    )
                    """.trimIndent()
                )
            }
        }

        fun create(context: Context): TelefamDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                TelefamDatabase::class.java,
                "telefam_encrypted.db"
            )
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
                .build()
        }
    }
}
