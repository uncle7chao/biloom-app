
-keep class com.follow.clash.models.** { *; }

-keep class com.follow.clash.service.models.** { *; }

# ---- AdMob(gms.ads) 引入的 androidx.work/Room：Room 以「类名字符串反射」
# 创建 WorkDatabase_Impl，R8 full mode（AGP 9 默认）会改名/剥离导致启动即崩
# （androidx.startup.InitializationProvider → Failed to create an instance
# of androidx.work.impl.WorkDatabase，2026-09-29 装机实测）。
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.RoomDatabase { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
