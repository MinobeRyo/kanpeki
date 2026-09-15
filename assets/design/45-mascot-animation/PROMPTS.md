# ImageGen prompts

Mode: built-in ImageGen. Reference: assets/brand/app-icon.png.

## Initial sheet

Use case: ui-mockup character animation asset sheet. Input image is the exact approved mascot identity. Generate an animation SPRITE SHEET, transparent alpha background, exactly 4 columns and 2 rows of equally sized cells, total image aspect 2:1, requested 2048x1024 pixels. NO grid lines, labels, shadows, scenery, phones, text, particles, ground or checkerboard. Each 512x512 cell contains the SAME flat vector-like notepad mascot in frontal view; center x within every cell exactly256, normally baseline400. Body ivory #F9FFE6 rectangle paper with very subtle palegreen #D9EBD5 backing layer, EXACTLY THREE dark slate #5C6673 curved binding rings at top, pale green tiny oval/rounded triangle nose, coral #FF5757 mouth, lightpink #FFC2C2 inside open mouth. No extra eyes, legs, arms, eyebrows, accessories or outline added. Use uploaded icon as model; remove only its square green backdrop. Consistent body geometry and scale across cells, body about290 wide and260 high, whole character including rings340 high, plentiful transparent padding. CLOSED mouth is a small friendly thin coral curved smile; OPEN mouth follows original large cheerful coral mouth shape with pink tongue. Row1 is four TALK animation frames all same body location shape and scale: cell1 closed smile, cell2 slightly open mouth, cell3 fully open original mouth, cell4 slightly open mouth identical tocell2. Row2 is four BOUNCE animation frames: cell1 neutral body closed smile at baseline400; cell2 anticipation body squash subtly wider and shorter baseline400 mouthsmallopen; cell3 airborne jump whole character 48pixels above baseline400, slight verticalstretch, happy open mouth; cell4 landing slight squash at baseline400, closedsmile. Keep all 8 characters whole with no cutoff and separate, do not include multiple characters in any cell, matchexactgrid. Real transparent background essential. Crisp clean 2D mascot UI animation assets, no painted textures or gradients.

## Selected revision

Preserve the 4-column by 2-row layout, cell order, character identity, expressions, positions, three binding rings, and mouth animations. Replace the transparent/noisy background with a uniform opaque pale green #D9EBD5. Remove white specks, rough halos, fragments, shadows and stray pixels. Crisp smooth clean vector-style edges, no texture, no labels. Keep aspect ratio 2:1. The initial transparency attempt was rejected after visual inspection; only the revised opaque version is included.

## Packaging

ffmpeg rectangular frame extraction and GIF/APNG encoding only. Character artwork and visual corrections were produced with ImageGen. Original sheet 1774×887; crops 443×443 on a 4×2 grid. Timings are stored in the ffconcat files.
