extension Catalog {
    /// Group key → five no-equipment and five gym exercises.
    static let exercises: [String: (noEquipment: [String], gym: [String])] = [
        "Rectus": (
            ["Standard Crunches", "V-Ups", "Bicycle Crunches", "Tuck Crunches (knees to chest)", "Hollow Body Hold"],
            ["Cable Crunches (Rope attachment)", "Weighted Decline Sit-ups", "Ab Coaster Machine", "Stability Ball Crunches", "Medicine Ball Slams"]),
        "Transversal": (
            ["Standard Plank", "Stomach Vacuums", "Dead Bug", "Bird-Dog", "Bear Crawl Hold"],
            ["Pallof Press (Cable)", "Ab Wheel Rollouts", "TRX Plank", "Bosu Ball Plank", "Landmine Anti-Rotation Sweeps"]),
        "Oblique": (
            ["Side Plank", "Russian Twists (Bodyweight)", "Heel Touches (Penguins)", "Side Jackknives", "Cross-body Mountain Climbers"],
            ["Cable Woodchoppers", "Dumbbell Side Bends", "Landmine 180s", "Weighted Russian Twist", "Captain's Chair Side Knee Raise"]),
        "Lower Abs": (
            ["Lying Leg Raises", "Flutter Kicks", "Reverse Crunches", "Scissor Kicks", "Pulse-Ups (Hips to ceiling)"],
            ["Hanging Leg Raises", "Captain's Chair Straight Leg Raise", "Decline Bench Reverse Crunch", "Cable Reverse Crunch (Ankle straps)", "Dragon Flags (Bench)"]),
        "Quads": (
            ["Air Squats", "Walking Lunges", "Step-Ups (on a sturdy chair)", "Bulgarian Split Squats", "Sissy Squats (Bodyweight)"],
            ["Barbell Back Squat", "Leg Extension Machine", "Leg Press", "Goblet Squat (Dumbbell/Kettlebell)", "Hack Squat Machine"]),
        "Hams": (
            ["Glute Bridges", "Single-Leg Glute Bridge", "Nordic Hamstring Curl (requires anchoring feet)", "Donkey Kicks", "Sliding Leg Curls (using socks on a smooth floor)"],
            ["Seated Leg Curl Machine", "Lying Leg Curl Machine", "Romanian Deadlift (Barbell/Dumbbell)", "Kettlebell Swings", "Glute-Ham Raise (GHR) Bench"]),
        "Inner (Thighs)": (
            ["Copenhagen Plank", "Sumo Squats (Wide stance)", "Side Lunges (Cossack Squats)", "Lying Inner Thigh Lifts", "Butterfly Stretch/Pulse"],
            ["Hip Adduction Machine", "Cable Adduction (Ankle strap)", "Wide Stance Leg Press", "Medicine Ball Squeeze (between knees)", "Sumo Deadlift"]),
        "Outer": (
            ["Side-Lying Leg Lifts", "Clamshells", "Fire Hydrants", "Lateral Band Walk (using improvised resistance if needed)", "Curtsy Lunges"],
            ["Hip Abduction Machine", "Cable Hip Abduction", "Banded Squats", "Weighted Step-Ups (Lateral)", "Machine Glute Kickback (angled)"]),
        "Standing": (
            ["Standing Calf Raise (Two legs)", "Single-Leg Calf Raise", "Stair Calf Raises (Heels hanging off step)", "Jump Rope", "Pogo Hops"],
            ["Smith Machine Calf Raise", "Standing Calf Raise Machine", "Leg Press Calf Raise", "Donkey Calf Raise Machine", "Weighted Vest Calf Jumps"]),
        "Seated": (
            ["Seated Soleus Hold (Static contraction)", "Seated Heel Raises (Manual resistance pushing down on knees)", "Deep Squat Hold (Heels down focus)", "Wall Sit with Heel Raise", "Crouched Walking"],
            ["Seated Calf Raise Machine", "Seated Dumbbell Calf Raise (Dumbbells on knees)", "Smith Machine Seated Raise (Bench required)", "Cable Soleus Press", "Plate Loaded Soleus Machine"]),
        "Hips": (
            ["Squat Jumps", "Frog Pumps", "Standing Leg Swings", "Hip Thrust (couch/bed edge)", "Sprinter Lunges"],
            ["Barbell Hip Thrust", "Cable Pull-Throughs", "Hip Press Machine", "Cable Kickbacks", "Reverse Hyper Machine"]),
        "Tibs": (
            ["Toe Raises (Standing against wall)", "Heel Walks", "Single-Leg Toe Raise", "Tibialis Raises (Sitting legs straight)", "Dorsiflexion Hold"],
            ["Dumbbell Tibialis Raise (Feet holding DB)", "Tib Bar Raises", "Banded Dorsiflexion", "Cable Dorsiflexion", "Kettlebell Toe Lift (Handle over toe)"]),
        "Mid": (
            ["Standard Push-ups", "Wide Grip Push-ups", "Plyometric (Clapping) Push-ups", "Archer Push-ups", "Isometric Chest Squeeze (Prayer pose)"],
            ["Flat Bench Press (Barbell)", "Flat Dumbbell Press", "Machine Chest Press", "Cable Flyes (Middle setting)", "Dumbbell Floor Press"]),
        "Upper": (
            ["Decline Push-ups (Feet elevated)", "Pike Push-ups (Chest focus)", "Hindu Push-ups", "Reverse Grip Push-ups", "Low-to-High Isometric Door Frame Press"],
            ["Incline Bench Press", "Incline Dumbbell Press", "Low-to-High Cable Flyes", "Incline Machine Press", "Landmine Press"]),
        "Lower": (
            ["Incline Push-ups (Hands elevated)", "Parallel Bar Dips (Between chairs/counters)", "Pseudo Planche Push-up", "Modified Cobra Push-up", "High-to-Low Isometric Door Press"],
            ["Chest Dips (Weighted)", "Decline Bench Press", "High-to-Low Cable Flyes", "Decline Dumbbell Flyes", "Pullover Machine (Chest bias)"]),
        "Inner (Chest)": (
            ["Diamond Push-ups", "Close-Grip Push-ups", "Cross-Body Push-ups", "Svend Press (pressing a book/object between palms)", "One-Arm Push-up (advanced)"],
            ["Pec Deck / Butterfly Machine", "Hex Press (Dumbbells pressed together)", "Single-Arm Cable Fly (crossing midline)", "Plate Press (Squeezing plate)", "Close-Grip Bench Press"]),
        "Traps": (
            ["Inverted Shrugs (Hanging from table/bar)", "Wall Angels", "Prone Cobras", "Handstand Shrugs (Wall assisted)", "Y-W-T Raises (Floor)"],
            ["Barbell Shrugs", "Dumbbell Shrugs", "Face Pulls (High pulley)", "Upright Rows", "Trap Bar Deadlift"]),
        "Lats": (
            ["Pull-ups / Chin-ups (Requires bar/ledge)", "Doorframe Rows", "Floor Sliders (Pulling body across floor)", "Elbow Presses (Lying on back, driving elbows down)", "Renegade Rows (Bodyweight tension)"],
            ["Lat Pulldowns", "Bent Over Barbell Row", "Single Arm Dumbbell Row", "Seated Cable Row", "Straight Arm Pulldown"]),
        "Lower Back": (
            ["Supermans", "Swimmers", "Bird-Dog", "Bridge Hold", "Reverse Snow Angels"],
            ["Deadlift (Conventional)", "Back Extension / Hyperextension Bench", "Good Mornings", "Rack Pulls", "Cable Pull-Throughs"]),
        "Neck": (
            ["Lying Neck Flexion (Head lifts)", "Lying Neck Extension (Face down head lifts)", "Isometric Front Press (Hand on forehead)", "Isometric Side Press", "Neck Rotations (Mobility)"],
            ["Neck Harness Extensions", "Neck Harness Flexion", "Plate Neck Curls (Plate on forehead)", "Cable Neck Rotation (Very light)", "4-Way Neck Machine"]),
        "Front": (
            ["Pike Push-ups", "Handstand Push-ups (Wall)", "Plank-to-Down-Dog", "Forward Arm Circles (Speed/Volume)", "Static Wall Handstand"],
            ["Overhead Barbell Press (Military Press)", "Dumbbell Shoulder Press", "Front Raises (Dumbbell/Plate)", "Arnold Press", "Landmine Press"]),
        "Lateral": (
            ["Doorframe Side Press (Isometric)", "Side Plank Rotations", "Bodyweight Lateral Raise (Lying on side, lifting torso)", "T-Plank", "Large Arm Circles"],
            ["Dumbbell Lateral Raise", "Cable Lateral Raise", "Machine Lateral Raise", "Upright Rows (Wide grip)", "Behind-the-Back Cable Raise"]),
        "Rear": (
            ["Reverse Iron Cross (Lying on back)", "Rear Delt Floor Flyes (T-Raise)", "Doorframe Face Pulls", "Thumb-Down T-Raises", "Prone Y Raises"],
            ["Face Pulls", "Reverse Pec Deck Machine", "Bent-Over Dumbbell Flyes", "Cable Rear Delt Flyes", "Barbell Rear Delt Row"]),
        "Rotator": (
            ["Internal Rotation (Isometric against wall)", "External Rotation (Isometric against wall)", "Scapular Push-ups", "Floor Wall Slides", "Lying Windmills"],
            ["Cable Internal Rotation", "Cable External Rotation", "Dumbbell \"Cuban Press\"", "Side-Lying Dumbbell External Rotation", "Face Pull with External Rotation"]),
        "Biceps": (
            ["Chin-ups (Requires bar)", "Leg Resistance Curls (Using your own leg as weight)", "Doorframe Curls", "Inverted Rows (Underhand grip - table/chairs)", "Isometric Bicep Hold (Clasping hands)"],
            ["Barbell Curl", "Dumbbell Hammer Curl", "Preacher Curl (Machine or Free weight)", "Incline Dumbbell Curl", "Cable Bicep Curl"]),
        "Triceps": (
            ["Bench Dips (Chair)", "Diamond Push-ups", "Bodyweight Tricep Extensions (against wall/counter)", "Close-Grip Push-ups", "L-Sit Hold"],
            ["Tricep Cable Pushdowns", "Skull Crushers (EZ Bar/Dumbbell)", "Overhead Tricep Extension", "Close-Grip Bench Press", "Weighted Dips"]),
        "Forearm": (
            ["Fingertip Push-ups", "Crab Walk", "Fist Clenches (High volume)", "Wall Finger Walks", "Doorframe Hang (Fingertips only)"],
            ["Wrist Curls (Palm up)", "Reverse Wrist Curls (Palm down)", "Reverse Barbell Curl", "Behind-the-Back Wrist Curl", "Wrist Roller"]),
        "Grip": (
            ["Dead Hangs (Requires Bar)", "Towel Wringing", "Book Pinch Hold (Holding heavy book by spine)", "Water Jug Carry", "Push-up Position Holds (on knuckles)"],
            ["Farmers Walk (Heavy Dumbbells)", "Plate Pinch Hold", "Captains of Crush (Grippers)", "Hex Dumbbell Hold (Holding the head of the DB)", "Fat Gripz Barbell Holds"]),
    ]
}
