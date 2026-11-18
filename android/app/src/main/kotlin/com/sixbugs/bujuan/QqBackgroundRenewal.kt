// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class QqBackgroundRenewal : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: JobParameters? = null
    private var headlessEngine: FlutterEngine? = null
    private val timeout = Runnable { finish(retry = true) }

    override fun onStartJob(params: JobParameters): Boolean {
        if (pending != null) return false
        pending = params
        activeJob = this
        handler.postDelayed(timeout, 90_000)
        // Begin asynchronously so even an immediate failure can call jobFinished.
        handler.post {
            if (pending === params) startRenewal(params)
        }
        return true
    }

    private fun startRenewal(params: JobParameters) {
        val engine = appEngine
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, RENEWAL_CHANNEL)
                .invokeMethod("renew", null, object : MethodChannel.Result {
                    override fun success(result: Any?) = complete(params, result != false)
                    override fun error(code: String, message: String?, details: Any?) =
                        complete(params, retry = true)
                    override fun notImplemented() = complete(params, retry = true)
                })
            return
        }

        try {
            val store = QqSessionStore(applicationContext)
            if (store.read() == null) {
                cancel(this)
                finish(retry = false)
                return
            }

            // Reuse the Dart renewal implementation without starting the UI or audio plugins.
            val worker = FlutterEngine(applicationContext, null, false)
            headlessEngine = worker
            val messenger = worker.dartExecutor.binaryMessenger
            MethodChannel(messenger, "buyu/qqmusic").setMethodCallHandler { call, reply ->
                if (pending !== params) {
                    reply.error("cancelled", "QQ续期任务已结束", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "readSession" -> reply.success(store.read())
                        "readWebSession" -> reply.success(QqWebSession.read())
                        "saveSession" -> {
                            store.saveAndUpdateWeb(call.arguments as String)
                            reply.success(null)
                        }
                        else -> reply.notImplemented()
                    }
                } catch (_: Exception) {
                    reply.error("session", "QQ登录状态暂时不可用", null)
                }
            }
            MethodChannel(messenger, RENEWAL_CHANNEL).setMethodCallHandler { call, reply ->
                if (call.method == "complete") {
                    reply.success(null)
                    handler.post { complete(params, call.arguments != false) }
                } else {
                    reply.notImplemented()
                }
            }
            val loader = FlutterInjector.instance().flutterLoader()
            worker.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "renewQqInBackground")
            )
        } catch (_: Exception) {
            finish(retry = true)
        }
    }

    private fun complete(params: JobParameters, retry: Boolean) {
        if (pending === params) finish(retry)
    }

    private fun finish(retry: Boolean) {
        val params = pending ?: return
        stopRenewal()
        jobFinished(params, retry)
    }

    private fun stopRenewal() {
        pending = null
        handler.removeCallbacks(timeout)
        if (activeJob === this) activeJob = null
        val worker = headlessEngine
        headlessEngine = null
        worker?.destroy()
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (pending === params) stopRenewal()
        return true
    }

    override fun onDestroy() {
        stopRenewal()
        super.onDestroy()
    }

    companion object {
        private const val JOB_ID = 7933
        private const val RETRY_DELAY = 5L * 60 * 1_000
        private const val RENEWAL_CHANNEL = "buyu/qq-renewal"
        private var appEngine: FlutterEngine? = null
        private var activeJob: QqBackgroundRenewal? = null

        fun attach(engine: FlutterEngine) {
            if (appEngine === engine) return
            // Both handlers run on Android's main thread. Finish the headless attempt
            // before the app engine can read or replace the encrypted session.
            activeJob?.takeIf { it.headlessEngine != null }?.finish(retry = true)
            appEngine = engine
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}
                override fun onEngineWillDestroy() {
                    if (appEngine === engine) appEngine = null
                }
            })
        }

        private fun scheduler(context: Context) =
            context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler

        fun schedule(context: Context) {
            if (Build.VERSION.SDK_INT < 23) return // Sessions persist only on API 23+.
            runCatching {
                val scheduler = scheduler(context)
                if (scheduler.allPendingJobs.any {
                    it.id == JOB_ID && it.initialBackoffMillis == RETRY_DELAY
                }) return
                scheduler.schedule(
                    JobInfo.Builder(JOB_ID, ComponentName(context, QqBackgroundRenewal::class.java))
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                        .setPeriodic(8L * 60 * 60 * 1_000)
                        .setBackoffCriteria(RETRY_DELAY, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                        .setPersisted(true)
                        .build()
                )
            }
        }

        fun cancel(context: Context) {
            runCatching { scheduler(context).cancel(JOB_ID) }
        }
    }
}
