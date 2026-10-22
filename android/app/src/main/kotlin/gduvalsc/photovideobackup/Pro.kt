package gduvalsc.photovideobackup

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import gduvalsc.pvb.core.Diag

/**
 * The one-time **Pro** upgrade (Google Play Billing, a non-consumable in-app product), the Android
 * counterpart of the iOS `StoreManager`. Free: the phone's gallery to one destination folder. Pro: SD
 * card / USB sources, a second destination folder, and the NAS (SMB).
 *
 * The price in the app comes from Google Play; it is set in the Play Console (not here).
 */
object Pro {
    const val PRODUCT_ID = "photovideobackup_pro"

    var isPro by mutableStateOf(false); private set
    var price by mutableStateOf<String?>(null); private set
    var isLoadingProduct by mutableStateOf(true); private set
    var productLoadFailed by mutableStateOf(false); private set
    var isBusy by mutableStateOf(false); private set
    var purchaseError by mutableStateOf<String?>(null)

    private var client: BillingClient? = null
    private var details: ProductDetails? = null

    fun init(app: Context) {
        if (client != null) return
        // Last known state: a paying user is not shown "free" while offline; Google Play corrects it as soon as it answers.
        isPro = Prefs.proCached
        client = BillingClient.newBuilder(app)
            .setListener(PurchasesUpdatedListener { r, list -> onPurchases(r, list) })
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        connect()
    }

    private fun connect() {
        val c = client ?: return
        if (c.isReady) { refresh(); return }
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(r: BillingResult) {
                if (r.responseCode == BillingClient.BillingResponseCode.OK) refresh()
                else { isLoadingProduct = false; productLoadFailed = true; Diag.write("[BILLING_ERROR] setup ${r.responseCode}") }
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    /** Reloads the product (price) and the purchases already made — also what "Restore Purchases" does. */
    fun refresh() {
        val c = client ?: return
        if (!c.isReady) { connect(); return }
        isLoadingProduct = true; productLoadFailed = false
        val query = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(PRODUCT_ID).setProductType(BillingClient.ProductType.INAPP).build(),
        )).build()
        c.queryProductDetailsAsync(query) { r, res ->
            isLoadingProduct = false
            val d = res.productDetailsList.firstOrNull()
            if (r.responseCode == BillingClient.BillingResponseCode.OK && d != null) {
                details = d
                price = d.oneTimePurchaseOfferDetails?.formattedPrice
                productLoadFailed = price == null
            } else productLoadFailed = true
        }
        c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()) { r, list ->
            if (r.responseCode == BillingClient.BillingResponseCode.OK) onPurchases(r, list)
        }
    }

    private fun onPurchases(r: BillingResult, list: List<Purchase>?) {
        isBusy = false
        when (r.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val mine = list.orEmpty().filter { PRODUCT_ID in it.products && it.purchaseState == Purchase.PurchaseState.PURCHASED }
                mine.filter { !it.isAcknowledged }.forEach { p ->
                    client?.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build()) { ar ->
                        if (ar.responseCode != BillingClient.BillingResponseCode.OK) Diag.write("[BILLING_ERROR] ack ${ar.responseCode}")
                    }
                }
                if (mine.isNotEmpty() || list != null) apply(mine.isNotEmpty())
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {}
            else -> { purchaseError = r.debugMessage.ifBlank { "Google Play (${r.responseCode})" }; Diag.write("[BILLING_ERROR] purchase ${r.responseCode}") }
        }
    }

    private fun apply(on: Boolean) { isPro = on; Prefs.proCached = on }

    /** Debug builds only: flips Pro locally so the gated flows can be tested without a Play purchase. */
    fun debugToggle() { if (gduvalsc.photovideobackup.BuildConfig.DEBUG) { isPro = !isPro; Prefs.proCached = isPro } }

    fun purchase(activity: Activity) {
        val d = details ?: return
        purchaseError = null; isBusy = true
        val p = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()
        val r = client?.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(p)).build())
        if (r == null || r.responseCode != BillingClient.BillingResponseCode.OK) { isBusy = false; purchaseError = r?.debugMessage }
    }
}
