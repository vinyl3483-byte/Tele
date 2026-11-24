package com.telefam.company.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.telefam.company.app.R

@Composable
fun Modifier.swipeBackEdge(
    enabled: Boolean = true,
    edgeWidth: Dp = 36.dp,
    triggerThreshold: Dp = 64.dp,
    onBack: () -> Unit
): Modifier {
    if (!enabled) return this
    val density = LocalDensity.current
    val currentOnBack by rememberUpdatedState(onBack)
    return this.pointerInput(enabled) {
        val edgePx = with(density) { edgeWidth.toPx() }
        val thresholdPx = with(density) { triggerThreshold.toPx() }
        var startedAtEdge = false
        var totalDragX = 0f
        var triggered = false
        detectHorizontalDragGestures(
            onDragStart = { offset ->
                startedAtEdge = offset.x <= edgePx
                totalDragX = 0f
                triggered = false
            },
            onDragEnd = {
                if (startedAtEdge && !triggered && totalDragX >= thresholdPx) {
                    triggered = true
                    currentOnBack()
                }
                startedAtEdge = false
                totalDragX = 0f
            },
            onDragCancel = {
                startedAtEdge = false
                totalDragX = 0f
            },
            onHorizontalDrag = { _, dragAmount ->
                if (!startedAtEdge || triggered) return@detectHorizontalDragGestures
                totalDragX += dragAmount
                if (totalDragX >= thresholdPx) {
                    triggered = true
                    currentOnBack()
                }
            }
        )
    }
}

@Composable
fun TelefamTopWave(
    modifier: Modifier = Modifier,
    height: Dp = 68.dp
) {
    val waveColor = MaterialTheme.colorScheme.primary
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
    ) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(w, 0f)
            lineTo(w, h * 0.72f)
            cubicTo(
                w * 0.80f, h * 1.05f,
                w * 0.62f, h * 0.35f,
                w * 0.45f, h * 0.52f
            )
            cubicTo(
                w * 0.25f, h * 0.72f,
                w * 0.12f, h * 0.88f,
                0f, h * 0.75f
            )
            close()
        }
        drawPath(path = path, color = waveColor)
    }
}

@Composable
fun TelefamBottomWave(
    modifier: Modifier = Modifier,
    height: Dp = 96.dp
) {
    val waveColor = MaterialTheme.colorScheme.primary
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
    ) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(0f, h * 0.22f)
            cubicTo(
                w * 0.22f, h * 0.62f,
                w * 0.36f, h * 0.20f,
                w * 0.52f, h * 0.40f
            )
            cubicTo(
                w * 0.74f, h * 0.65f,
                w * 0.88f, h * 0.12f,
                w, h * 0.28f
            )
            lineTo(w, h)
            lineTo(0f, h)
            close()
        }
        drawPath(path = path, color = waveColor)
    }
}

@Composable
fun TelefamBrandHeader(
    modifier: Modifier = Modifier,
    logoSize: Dp = 68.dp
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Image(
            painter = painterResource(id = R.drawable.ic_telefam_logo),
            contentDescription = stringResource(id = R.string.app_name),
            modifier = Modifier.size(logoSize)
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = stringResource(id = R.string.app_name),
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = stringResource(id = R.string.tagline),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
