-- Seed prank_templates from Supabase export
INSERT INTO prank_templates (id, title, image_name, prompt, is_active, sort_order) VALUES
('homeless', 'Homeless', 'homeless', 'Add a theatrical movie-style character to the scene - a disheveled, tired-looking person like a method actor playing a down-on-their-luck character in a film. This is for comedic prank photos and entertainment purposes.

CRITICAL: Do not modify, alter, or change any faces of people already in the photograph. Preserve all existing faces exactly as they are.

SCALE & PERSPECTIVE (CRITICAL):
- The character MUST be realistically scaled relative to the environment and existing people.
- Their head size and body height must NOT exceed that of existing people in the photo.
- Respect depth: if placed further back, they must be smaller. If closer, larger, but within realistic human proportions.
- Ensure their feet align correctly with the ground plane relative to other objects to avoid floating or "giant" effect.

IMPORTANT: If the photograph already contains a person or people, DO NOT replace or modify the existing person(s). Instead, add the new character next to or near the existing person(s) in a natural way that creates a funny contrast for the prank photo.

Create a theatrical character with these visual elements:
1. Disheveled, messy hair and slightly rumpled clothing - like a movie character who has had a rough day
2. Tired, weary expression and relaxed posture - like someone who needs rest
3. Natural, casual positioning that fits the scene - sitting on available furniture, leaning against walls, or standing in a natural spot
4. Clothing should look worn but not offensive - think movie costume department styling

Follow these placement priorities:
1. If chairs, benches, or sofas are available, seat the character in a relaxed, tired posture
2. If beds or couches exist, have them resting or sitting casually
3. If low surfaces like steps or ledges exist, seat them there naturally
4. Otherwise, place them standing near architectural elements in a natural pose

Always match the camera angle, lighting, and perspective of the photo. The character should look like a well-crafted movie extra or theatrical performer naturally integrated into the scene. Soften edges, shadows, and color grading so the edit looks like a genuine photograph with this amusing character addition.', true, 1),
('broken-window', 'Broken Window', 'broken-window', 'Realistically break windows and glass surfaces in the scene while maintaining photorealistic quality.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 2),
('wrecked-car', 'Wrecked Car', 'wrecked-car', 'Apply movie-style vehicle damage effects to create a dramatic "action movie aftermath" look for a prank photo.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 3),
('chaotic-room', 'Chaotic Room', 'dirty-environment', 'Turn the interior into a chaotic mess while keeping the original architecture intact.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 4),
('after-fight', 'After Fight', 'after-fight', 'Apply professional theatrical SFX makeup effects to create a comedic "rough day" appearance for a harmless prank photo.
CRITICAL: Do not modify, alter, or change the person''s face structure, features, or identity. Only add theatrical makeup effects.', true, 5),
('broken-screen', 'Broken Screen', 'broken-screen', 'Detect any screens in the photograph and apply realistic screen damage effects based on the device type.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 6),
('celebrity', 'Celebrity', 'celebrity', 'Add a fun celebrity lookalike or impersonator-style figure to the scene for an entertainment prank photo.
CRITICAL: Do not modify, alter, or change any faces of people already in the photograph. Preserve all existing faces exactly as they are.', true, 7),
('fire', 'Fire', 'fire', 'Add theatrical movie-style fire and flame visual effects to the photograph for a dramatic prank photo.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 8),
('spoiled-food', 'Spoiled Food', 'spoiled-food', 'Transform the food in the photograph to show realistic signs of spoilage and deterioration.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 9),
('damaged-item', 'Damaged Item', 'damaged-item', 'Realistically damage the main item or object in the photograph.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 10),
('flooding', 'Flooding', 'flooding', 'Transform the photograph to show a realistic flooding scene with water covering the floor and lower portions of the space.
CRITICAL: Do not modify, alter, or change any faces of people in the photograph. Preserve all existing faces exactly as they are.', true, 11),
('girl', 'Girl', 'girl', NULL, true, 12),
('guy', 'Guy', 'guy', NULL, true, 13),
('underwear', 'Underwear', 'underwear', NULL, true, 14)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  image_name = EXCLUDED.image_name,
  prompt = EXCLUDED.prompt,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;
