package io.github.mertcandanzz.aws_liveness_for_flutter

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraPermissionTest {
    @Test
    fun `current status without a request`() {
        assertEquals(CameraPermissionStatusMessage.GRANTED, CameraPermission.currentStatus(true, null))
        assertEquals(CameraPermissionStatusMessage.GRANTED, CameraPermission.currentStatus(true, false))
        assertEquals(CameraPermissionStatusMessage.DENIED, CameraPermission.currentStatus(false, true))
        // Never asked and "don't ask again" look the same before a request.
        assertEquals(CameraPermissionStatusMessage.NOT_DETERMINED, CameraPermission.currentStatus(false, false))
        assertEquals(CameraPermissionStatusMessage.NOT_DETERMINED, CameraPermission.currentStatus(false, null))
    }

    @Test
    fun `status after a request`() {
        assertEquals(CameraPermissionStatusMessage.GRANTED, CameraPermission.statusAfterRequest(true, false))
        assertEquals(CameraPermissionStatusMessage.DENIED, CameraPermission.statusAfterRequest(false, true))
        assertEquals(
            CameraPermissionStatusMessage.PERMANENTLY_DENIED,
            CameraPermission.statusAfterRequest(false, false),
        )
    }

    @Test
    fun `pre-check errors`() {
        assertNull(CameraPermission.errorFor(CameraPermissionStatusMessage.GRANTED))
        assertEquals(
            ErrorCodeMessage.CAMERA_PERMISSION_DENIED,
            CameraPermission.errorFor(CameraPermissionStatusMessage.DENIED),
        )
        assertEquals(
            ErrorCodeMessage.CAMERA_PERMISSION_DENIED,
            CameraPermission.errorFor(CameraPermissionStatusMessage.NOT_DETERMINED),
        )
        assertEquals(
            ErrorCodeMessage.CAMERA_PERMISSION_PERMANENTLY_DENIED,
            CameraPermission.errorFor(CameraPermissionStatusMessage.PERMANENTLY_DENIED),
        )
        assertEquals(
            ErrorCodeMessage.CAMERA_PERMISSION_PERMANENTLY_DENIED,
            CameraPermission.errorFor(CameraPermissionStatusMessage.RESTRICTED),
        )
    }

    @Test
    fun `concurrent permission requests share one prompt and reply once`() {
        val requests = PermissionRequests()
        val replies = mutableListOf<CameraPermissionStatusMessage>()

        val id = assertNotNull(requests.add { replies += it }, "first caller shows the prompt")
        assertNull(requests.add { replies += it }, "second caller joins it")
        assertTrue(requests.isPending(id))

        assertTrue(requests.complete(id, CameraPermissionStatusMessage.GRANTED))
        assertFalse(requests.complete(id, CameraPermissionStatusMessage.DENIED))

        assertEquals(List(2) { CameraPermissionStatusMessage.GRANTED }, replies)
        assertFalse(requests.isPending(id))
    }

    @Test
    fun `an old permission Activity cannot complete a newer request`() {
        val requests = PermissionRequests()
        val first = mutableListOf<CameraPermissionStatusMessage>()
        val second = mutableListOf<CameraPermissionStatusMessage>()

        val oldId = assertNotNull(requests.add { first += it })
        requests.complete(oldId, CameraPermissionStatusMessage.GRANTED)
        val newId = assertNotNull(requests.add { second += it }, "a new prompt after the reply")
        assertNotEquals(oldId, newId)

        // The old Activity's onDestroy runs after the new request was queued.
        assertFalse(requests.complete(oldId, CameraPermissionStatusMessage.NOT_DETERMINED))
        assertFalse(requests.isPending(oldId))
        assertTrue(second.isEmpty(), "the newer caller still waits for its own prompt")

        assertTrue(requests.complete(newId, CameraPermissionStatusMessage.DENIED))
        assertEquals(listOf(CameraPermissionStatusMessage.GRANTED), first)
        assertEquals(listOf(CameraPermissionStatusMessage.DENIED), second)
    }
}
