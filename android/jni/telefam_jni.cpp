#include <jni.h>
#include <string>
#include <vector>
#include "telefam_core.h"

namespace {
std::string jstr_to_std(JNIEnv* env, jstring s) {
    if (!s) return "";
    const char* chars = env->GetStringUTFChars(s, nullptr);
    std::string out(chars ? chars : "");
    if (chars) env->ReleaseStringUTFChars(s, chars);
    return out;
}
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeCreateEngine(
    JNIEnv* env, jobject, jstring vaultPath, jbyteArray masterKey32
) {
    if (!masterKey32 || env->GetArrayLength(masterKey32) != 32) return 0L;
    std::string path = jstr_to_std(env, vaultPath);
    jbyte* keyBytes = env->GetByteArrayElements(masterKey32, nullptr);
    telefam_engine_t* eng = telefam_engine_create(
        path.c_str(),
        reinterpret_cast<const uint8_t*>(keyBytes),
        32
    );
    env->ReleaseByteArrayElements(masterKey32, keyBytes, JNI_ABORT);
    return reinterpret_cast<jlong>(eng);
}

JNIEXPORT void JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeDestroyEngine(
    JNIEnv*, jobject, jlong handle
) {
    if (handle != 0L) {
        telefam_engine_destroy(reinterpret_cast<telefam_engine_t*>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeDeviceFingerprint(
    JNIEnv* env, jobject, jstring platform, jstring model, jstring deviceName, jstring hwId, jstring salt
) {
    char out[65]{};
    telefam_compute_device_fingerprint(
        jstr_to_std(env, platform).c_str(),
        jstr_to_std(env, model).c_str(),
        jstr_to_std(env, deviceName).c_str(),
        jstr_to_std(env, hwId).c_str(),
        jstr_to_std(env, salt).c_str(),
        out, sizeof(out)
    );
    return env->NewStringUTF(out);
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeIpFingerprint(
    JNIEnv* env, jobject, jstring ip, jstring subnet, jstring salt
) {
    char out[65]{};
    telefam_compute_ip_fingerprint(
        jstr_to_std(env, ip).c_str(),
        jstr_to_std(env, subnet).c_str(),
        jstr_to_std(env, salt).c_str(),
        out, sizeof(out)
    );
    return env->NewStringUTF(out);
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeValidateEmail(
    JNIEnv* env, jobject, jstring email
) {
    return telefam_validate_email(jstr_to_std(env, email).c_str()) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeValidateOtp(
    JNIEnv* env, jobject, jstring otp
) {
    return telefam_validate_otp(jstr_to_std(env, otp).c_str()) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeValidateAge13Plus(
    JNIEnv*, jobject, jint by, jint bm, jint bd, jint ny, jint nm, jint nd
) {
    return telefam_validate_age_13_plus(by, bm, bd, ny, nm, nd) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeValidatePhone(
    JNIEnv* env, jobject, jstring countryIso, jstring phone
) {
    return telefam_validate_phone_number(
        jstr_to_std(env, countryIso).c_str(),
        jstr_to_std(env, phone).c_str()
    ) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeSuggestCountryIso(
    JNIEnv* env, jobject, jstring carrierIso, jstring tzId, jstring localeIso
) {
    char buf[4]{};
    telefam_suggest_country_iso(
        jstr_to_std(env, carrierIso).c_str(),
        jstr_to_std(env, tzId).c_str(),
        jstr_to_std(env, localeIso).c_str(),
        buf, sizeof(buf)
    );
    return env->NewStringUTF(buf);
}

JNIEXPORT jobjectArray JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeAutofillFromEmail(
    JNIEnv* env, jobject, jstring email
) {
    char fullName[128]{};
    char username[64]{};
    telefam_autofill_profile_from_email(
        jstr_to_std(env, email).c_str(),
        fullName, sizeof(fullName),
        username, sizeof(username)
    );
    jclass strCls = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray(2, strCls, nullptr);
    env->SetObjectArrayElement(arr, 0, env->NewStringUTF(fullName));
    env->SetObjectArrayElement(arr, 1, env->NewStringUTF(username));
    return arr;
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeSanitizeError(
    JNIEnv* env, jobject, jint httpStatus, jstring rawError
) {
    char buf[160]{};
    telefam_sanitize_error(httpStatus, jstr_to_std(env, rawError).c_str(), buf, sizeof(buf));
    return env->NewStringUTF(buf);
}

JNIEXPORT jlongArray JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeCheckCooldown(
    JNIEnv* env, jobject, jlong handle, jstring email, jlong nowSec
) {
    telefam_cooldown_state_t st{};
    if (handle != 0L) {
        telefam_otp_check_cooldown(reinterpret_cast<telefam_engine_t*>(handle), jstr_to_std(env, email).c_str(), nowSec, &st);
    } else {
        st.can_resend = 1;
    }
    jlong vals[4] = {st.remaining_seconds, st.tier_index, st.resend_count, st.can_resend};
    jlongArray arr = env->NewLongArray(4);
    env->SetLongArrayRegion(arr, 0, 4, vals);
    return arr;
}

JNIEXPORT jlongArray JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeRecordOtpSend(
    JNIEnv* env, jobject, jlong handle, jstring email, jlong nowSec
) {
    telefam_cooldown_state_t st{};
    telefam_status_t res = TELEFAM_ERR_GENERIC;
    if (handle != 0L) {
        res = telefam_otp_record_send(reinterpret_cast<telefam_engine_t*>(handle), jstr_to_std(env, email).c_str(), nowSec, &st);
    }
    jlong vals[5] = {static_cast<jlong>(res), st.remaining_seconds, st.tier_index, st.resend_count, st.can_resend};
    jlongArray arr = env->NewLongArray(5);
    env->SetLongArrayRegion(arr, 0, 5, vals);
    return arr;
}

JNIEXPORT void JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeResetCooldown(
    JNIEnv* env, jobject, jlong handle, jstring email
) {
    if (handle != 0L) {
        telefam_otp_reset_cooldown(reinterpret_cast<telefam_engine_t*>(handle), jstr_to_std(env, email).c_str());
    }
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeAllowRateLimit(
    JNIEnv* env, jobject, jlong handle, jstring acc, jstring devFp, jstring ipFp, jlong nowSec
) {
    if (handle == 0L) return JNI_FALSE;
    return telefam_rate_limit_allow(
        reinterpret_cast<telefam_engine_t*>(handle),
        jstr_to_std(env, acc).c_str(),
        jstr_to_std(env, devFp).c_str(),
        jstr_to_std(env, ipFp).c_str(),
        nowSec
    ) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeOutboxEnqueue(
    JNIEnv* env, jobject, jlong handle, jstring mutId, jstring action, jstring payloadJson, jlong nowMs
) {
    if (handle == 0L) return TELEFAM_ERR_GENERIC;
    return telefam_outbox_enqueue(
        reinterpret_cast<telefam_engine_t*>(handle),
        jstr_to_std(env, mutId).c_str(),
        jstr_to_std(env, action).c_str(),
        jstr_to_std(env, payloadJson).c_str(),
        nowMs
    );
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeOutboxPeekBatch(
    JNIEnv* env, jobject, jlong handle, jint maxItems
) {
    if (handle == 0L) return env->NewStringUTF("[]");
    std::vector<char> buf(65536, 0);
    if (telefam_outbox_peek_batch(reinterpret_cast<telefam_engine_t*>(handle), maxItems, buf.data(), buf.size()) == TELEFAM_OK) {
        return env->NewStringUTF(buf.data());
    }
    return env->NewStringUTF("[]");
}

JNIEXPORT void JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeOutboxAck(
    JNIEnv* env, jobject, jlong handle, jstring mutId
) {
    if (handle != 0L) {
        telefam_outbox_ack(reinterpret_cast<telefam_engine_t*>(handle), jstr_to_std(env, mutId).c_str());
    }
}

JNIEXPORT jboolean JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeAllowFollowRateLimit(
    JNIEnv* env, jobject, jlong handle, jstring accountKey, jlong nowSec
) {
    if (handle == 0L) return JNI_FALSE;
    return telefam_follow_rate_limit_allow(
        reinterpret_cast<telefam_engine_t*>(handle),
        jstr_to_std(env, accountKey).c_str(),
        nowSec
    ) == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeRelationshipState(
    JNIEnv*, jobject, jboolean isFollowing, jboolean followsMe
) {
    return telefam_relationship_state(
        isFollowing == JNI_TRUE ? 1 : 0,
        followsMe == JNI_TRUE ? 1 : 0
    );
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeComputeFrameDHash(
    JNIEnv* env, jobject, jbyteArray rgbaPixels, jint width, jint height
) {
    if (!rgbaPixels || width <= 0 || height <= 0) return env->NewStringUTF("");
    jsize len = env->GetArrayLength(rgbaPixels);
    if (static_cast<int64_t>(len) < static_cast<int64_t>(width) * static_cast<int64_t>(height) * 4LL) {
        return env->NewStringUTF("");
    }
    jbyte* ptr = env->GetByteArrayElements(rgbaPixels, nullptr);
    char out[17]{};
    telefam_compute_frame_dhash(reinterpret_cast<const uint8_t*>(ptr), width, height, out, sizeof(out));
    env->ReleaseByteArrayElements(rgbaPixels, ptr, JNI_ABORT);
    return env->NewStringUTF(out);
}

JNIEXPORT jstring JNICALL
Java_com_telefam_company_app_core_TelefamNativeBridge_nativeComputeMediaContentId(
    JNIEnv* env, jobject,
    jstring mediaKind,
    jstring frameHashesCsv,
    jstring audioFpHex,
    jint width,
    jint height,
    jlong durationMs,
    jstring salt
) {
    char out[65]{};
    telefam_compute_media_content_id(
        jstr_to_std(env, mediaKind).c_str(),
        jstr_to_std(env, frameHashesCsv).c_str(),
        jstr_to_std(env, audioFpHex).c_str(),
        width,
        height,
        durationMs,
        jstr_to_std(env, salt).c_str(),
        out,
        sizeof(out)
    );
    return env->NewStringUTF(out);
}

} // extern "C"
