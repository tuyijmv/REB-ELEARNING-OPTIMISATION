<?php
/**
 * REB E-Learning Customization Script
 *
 * Applies all REB branding customizations to a freshly installed Moodle:
 *  - Sets Moove as the active theme
 *  - Uploads generated branding images (logo, favicon, login/banner)
 *  - Applies REB brand colors + custom SCSS
 *  - Creates course categories (Science, Languages, Humanities)
 *  - Creates sample courses grouped into those categories
 *  - Generates and uploads a cover image for every course
 *  - Sets site name, description and a few appearance settings
 *
 * The script is idempotent: re-running it will not duplicate courses or
 * categories and will simply refresh the branding assets and settings.
 *
 * Run it inside the Moodle container, e.g.:
 *   php /var/www/html/moodle_app/customize_moodle.php
 */

define('CLI_SCRIPT', true);

// ---------------------------------------------------------------------------
// Locate config.php. Moodle 5.1 keeps config.php at the install root and the
// web server document root is the 'public/' sub-directory, so we search the
// most likely locations rather than assuming one fixed path.
// ---------------------------------------------------------------------------
$config_candidates = [
    __DIR__ . '/config.php',
    '/var/www/html/moodle_app/config.php',
    '/var/www/html/config.php',
];
$config_found = false;
foreach ($config_candidates as $candidate) {
    if (file_exists($candidate)) {
        require_once($candidate);
        $config_found = true;
        break;
    }
}
if (!$config_found) {
    fwrite(STDERR, "ERROR: Could not locate config.php. Is Moodle installed yet?\n");
    exit(1);
}

require_once($CFG->libdir . '/adminlib.php');
require_once($CFG->libdir . '/coursecatlib.php');
require_once($CFG->dirroot . '/course/lib.php');

global $DB, $CFG;

echo "=== REB E-Learning Customization Script ===\n\n";

// ===========================================================================
// 0. HELPERS: file uploads using Moodle file API
// ===========================================================================

/** Store a file in a theme_moove stored-file setting (logo, favicon, ...). */
function reb_upload_theme_file($filearea, $path, $filename) {
    $sysctx = context_system::instance();
    $fs = get_file_storage();
    $fs->delete_area_files($sysctx->id, 'theme_moove', $filearea, 0);
    $record = [
        'contextid' => $sysctx->id,
        'component' => 'theme_moove',
        'filearea'  => $filearea,
        'itemid'    => 0,
        'filepath'  => '/',
        'filename'  => $filename,
    ];
    return $fs->create_file_from_pathname($record, $path);
}

/** Store a course overview/cover image for a given course. */
function reb_upload_course_cover($courseid, $path, $filename) {
    $ctx = context_course::instance($courseid);
    $fs = get_file_storage();
    $fs->delete_area_files($ctx->id, 'course', 'overviewfiles', 0);
    $record = [
        'contextid' => $ctx->id,
        'component' => 'course',
        'filearea'  => 'overviewfiles',
        'itemid'    => 0,
        'filepath'  => '/',
        'filename'  => $filename,
    ];
    return $fs->create_file_from_pathname($record, $path);
}

// ===========================================================================
// 1. SITE NAME AND DESCRIPTION
// ===========================================================================
echo "--- Setting site name and description ---\n";
set_config('fullname', 'REB E-Learning Portal', 'core');
$DB->set_field('course', 'fullname', 'REB E-Learning Portal', ['id' => SITEID]);
$DB->set_field('course', 'shortname', 'REB', ['id' => SITEID]);
$DB->set_field('course', 'summary',
    '<p>Welcome to the <strong>Rwanda Education Board E-Learning Portal</strong>. Access quality education resources anytime, anywhere.</p>',
    ['id' => SITEID]);
echo "  [OK] Site name: REB E-Learning Portal\n";

// ===========================================================================
// 2. ACTIVATE MOOVE THEME
// ===========================================================================
echo "\n--- Activating Moove theme ---\n";
$themename = 'moove';
$themedir = $CFG->dirroot . '/theme/' . $themename;
if (!is_dir($themedir)) {
    // Moodle 5.1+ keeps themes under the public web root.
    $themedir = $CFG->dirroot . '/public/theme/' . $themename;
}
if (!is_dir($themedir)) {
    echo "  [WARNING] Moove theme directory not found. Skipping theme activation.\n";
} else {
    set_config('theme', $themename);
    echo "  [OK] Theme set to: $themename\n";
}

// ===========================================================================
// 3. MOOVE BRAND COLORS + CUSTOM SCSS
// ===========================================================================
echo "\n--- Applying REB brand colors and SCSS ---\n";

$moove_settings = [
    'brandcolor'          => '#00A0DC', // Rwanda blue
    'secondarymenucolor'  => '#00A651', // Rwanda green
    'fontsite'            => 'Inter',   // Modern font (valid Moove option)
    'enablecourseindex'   => '1',       // Enable course index
];

foreach ($moove_settings as $key => $value) {
    set_config($key, $value, 'theme_moove');
    echo "  [OK] theme_moove/$key = $value\n";
}

$custom_scss = '
/* ===== REB E-Learning Custom Styles ===== */
@import url("https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap");

body {
    font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
    -webkit-font-smoothing: antialiased;
}

.navbar {
    background: linear-gradient(135deg, #003366 0%, #00264D 100%) !important;
    box-shadow: 0 2px 10px rgba(0,0,0,0.15);
    backdrop-filter: blur(10px);
}

.card {
    border: none !important;
    border-radius: 16px !important;
    box-shadow: 0 4px 15px rgba(0,0,0,0.08) !important;
    transition: transform 0.3s ease, box-shadow 0.3s ease !important;
    overflow: hidden;
}
.card:hover {
    transform: translateY(-4px) !important;
    box-shadow: 0 8px 30px rgba(0,0,0,0.12) !important;
}

.coursebox .card,
.course-card {
    border-radius: 16px !important;
    overflow: hidden;
}
.course-card .card-img-top,
.coursebox .courseimage img {
    border-radius: 16px 16px 0 0 !important;
    object-fit: cover;
    height: 180px;
}

.category-card {
    background: linear-gradient(135deg, rgba(0,160,220,0.05), rgba(0,166,81,0.05));
    border-radius: 16px;
}

.btn-primary {
    background: linear-gradient(135deg, #00A0DC, #0088CC) !important;
    border: none !important;
    border-radius: 10px !important;
    font-weight: 600 !important;
    padding: 10px 24px !important;
    box-shadow: 0 3px 10px rgba(0,160,220,0.3) !important;
}
.btn-primary:hover {
    background: linear-gradient(135deg, #0088CC, #006FAA) !important;
    transform: translateY(-2px) !important;
    box-shadow: 0 5px 15px rgba(0,160,220,0.4) !important;
}
.btn-secondary {
    background: linear-gradient(135deg, #00A651, #008C44) !important;
    border: none !important;
    border-radius: 10px !important;
    color: white !important;
}

.login-wrapper,
#page-login-index {
    background: linear-gradient(135deg, #003366 0%, #00264D 50%, #001A33 100%) !important;
}
.login-container .card,
#page-login-index .card {
    background: rgba(255,255,255,0.95) !important;
    backdrop-filter: blur(20px) !important;
    border-radius: 24px !important;
    box-shadow: 0 20px 60px rgba(0,0,0,0.3) !important;
}

#page-header {
    background: linear-gradient(135deg, #003366, #00264D) !important;
    color: white !important;
    border-radius: 0 0 24px 24px !important;
    padding: 2rem !important;
    margin-bottom: 1.5rem;
}
#page-header h1,
#page-header .page-header-headings h1 {
    color: white !important;
}

#page-footer {
    background: linear-gradient(135deg, #003366, #00264D) !important;
    color: rgba(255,255,255,0.8) !important;
    border-radius: 24px 24px 0 0 !important;
    margin-top: 2rem;
}

[data-region="drawer"] {
    background: linear-gradient(180deg, #00264D, #001A33) !important;
    border-radius: 0 16px 16px 0 !important;
}
[data-region="drawer"] .list-group-item {
    background: transparent !important;
    color: rgba(255,255,255,0.8) !important;
    border-color: rgba(255,255,255,0.1) !important;
}
[data-region="drawer"] .list-group-item:hover {
    background: rgba(0,160,220,0.15) !important;
    color: white !important;
}

.progress-bar {
    background: linear-gradient(90deg, #00A651, #FFC726) !important;
    border-radius: 10px !important;
}

.badge {
    border-radius: 8px !important;
    font-weight: 500 !important;
    padding: 4px 10px !important;
}

.navbar::after {
    content: "";
    display: block;
    height: 3px;
    background: linear-gradient(90deg, #00A0DC 33%, #00A651 33%, #00A651 66%, #FFC726 66%);
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
}
';

set_config('scss', $custom_scss, 'theme_moove');
echo "  [OK] theme_moove/scss applied (REB glassmorphism, brand colors)\n";

// ===========================================================================
// 4. UPLOAD BRANDING IMAGES
// ===========================================================================
echo "\n--- Uploading branding images ---\n";

$assets_dir = '/var/www/html/moodle_app/assets/images';

if (is_dir($themedir)) {
    if (file_exists($assets_dir . '/logo.png')) {
        reb_upload_theme_file('logo', $assets_dir . '/logo.png', 'logo.png');
        echo "  [OK] Uploaded theme logo\n";
    } else {
        echo "  [WARN] Logo not found at {$assets_dir}/logo.png\n";
    }
    if (file_exists($assets_dir . '/favicon.png')) {
        reb_upload_theme_file('favicon', $assets_dir . '/favicon.png', 'favicon.png');
        echo "  [OK] Uploaded theme favicon\n";
    } else {
        echo "  [WARN] Favicon not found at {$assets_dir}/favicon.png\n";
    }
    if (file_exists($assets_dir . '/login-banner.png')) {
        reb_upload_theme_file('loginbgimg', $assets_dir . '/login-banner.png', 'login-banner.png');
        echo "  [OK] Uploaded login background\n";
    } else {
        echo "  [WARN] Login banner not found at {$assets_dir}/login-banner.png\n";
    }
} else {
    echo "  [SKIP] Moove theme not found - skipping image uploads.\n";
}

// ===========================================================================
// 5. COURSE CATEGORIES
// ===========================================================================
echo "\n--- Creating course categories ---\n";

$categories_data = [
    [
        'name'        => 'Science',
        'description' => '<p>Explore the wonders of science through interactive lessons in Biology, Chemistry, Physics and Mathematics. Build critical thinking and analytical skills.</p>',
        'idnumber'    => 'CAT-SCIENCE',
    ],
    [
        'name'        => 'Languages',
        'description' => '<p>Develop your communication skills in English, Kinyarwanda, French and other languages. Master reading, writing, speaking and listening.</p>',
        'idnumber'    => 'CAT-LANGUAGES',
    ],
    [
        'name'        => 'Humanities',
        'description' => '<p>Discover history, geography, economics and social studies. Understand the world around you and develop informed perspectives.</p>',
        'idnumber'    => 'CAT-HUMANITIES',
    ],
];

$created_categories = [];
foreach ($categories_data as $cat_data) {
    $existing = $DB->get_record('course_categories', ['idnumber' => $cat_data['idnumber']]);
    if ($existing) {
        echo "  [SKIP] Category '{$cat_data['name']}' already exists (id: {$existing->id})\n";
        $created_categories[$cat_data['idnumber']] = $existing->id;
    } else {
        $cat = core_course_category::create([
            'name'         => $cat_data['name'],
            'description'  => $cat_data['description'],
            'descriptionformat' => FORMAT_HTML,
            'idnumber'     => $cat_data['idnumber'],
            'parent'       => 0,
            'visible'      => 1,
        ]);
        echo "  [OK] Created category: {$cat_data['name']} (id: {$cat->id})\n";
        $created_categories[$cat_data['idnumber']] = $cat->id;
    }
}

// ===========================================================================
// 6. SAMPLE COURSES
// ===========================================================================
echo "\n--- Creating sample courses ---\n";

$courses_data = [
    [
        'fullname'  => 'Mathematics Grade 10',
        'shortname' => 'MATH-G10',
        'category'  => $created_categories['CAT-SCIENCE'],
        'summary'   => '<p>Master key mathematical concepts including algebra, geometry, trigonometry, and statistics. Develop problem-solving skills essential for scientific thinking.</p>',
        'numsections' => 12,
        'color'     => '#0061A8',
    ],
    [
        'fullname'  => 'Chemistry Grade 11',
        'shortname' => 'CHEM-G11',
        'category'  => $created_categories['CAT-SCIENCE'],
        'summary'   => '<p>Explore the world of atoms, molecules, and chemical reactions. Learn about the periodic table, organic chemistry, and laboratory techniques.</p>',
        'numsections' => 12,
        'color'     => '#00843D',
    ],
    [
        'fullname'  => 'Biology Grade 10',
        'shortname' => 'BIO-G10',
        'category'  => $created_categories['CAT-SCIENCE'],
        'summary'   => '<p>Discover the science of life - from cells and genetics to ecosystems and evolution. Engage with interactive labs and real-world applications.</p>',
        'numsections' => 12,
        'color'     => '#1B7F79',
    ],
    [
        'fullname'  => 'English Grade 9',
        'shortname' => 'ENG-G09',
        'category'  => $created_categories['CAT-LANGUAGES'],
        'summary'   => '<p>Strengthen your English language skills through reading comprehension, creative writing, grammar, and vocabulary building exercises.</p>',
        'numsections' => 12,
        'color'     => '#7A1F2B',
    ],
    [
        'fullname'  => 'Kinyarwanda Grade 9',
        'shortname' => 'KIN-G09',
        'category'  => $created_categories['CAT-LANGUAGES'],
        'summary'   => '<p>Deepen your knowledge of Kinyarwanda language and literature. Study grammar, creative writing, oral traditions, and cultural heritage.</p>',
        'numsections' => 12,
        'color'     => '#5A3E85',
    ],
    [
        'fullname'  => 'History Grade 11',
        'shortname' => 'HIS-G11',
        'category'  => $created_categories['CAT-HUMANITIES'],
        'summary'   => '<p>Journey through world and African history. Analyze key events, movements, and civilizations that shaped the modern world.</p>',
        'numsections' => 12,
        'color'     => '#B5651D',
    ],
];

$created_courses = [];
foreach ($courses_data as $course_data) {
    $existing = $DB->get_record('course', ['shortname' => $course_data['shortname']]);
    if ($existing) {
        echo "  [SKIP] Course '{$course_data['shortname']}' already exists (id: {$existing->id})\n";
        $created_courses[$course_data['shortname']] = $existing;
        continue;
    }
    $course = create_course((object) array_merge($course_data, [
        'summaryformat' => FORMAT_HTML,
        'format'        => 'topics',
        'visible'       => 1,
        'startdate'     => time(),
        'enddate'       => 0,
        'lang'          => '',
    ]));
    echo "  [OK] Created course: {$course_data['fullname']} ({$course_data['shortname']}) (id: {$course->id})\n";
    $created_courses[$course_data['shortname']] = $course;
}

// ===========================================================================
// 7. COURSE COVER IMAGES
// ===========================================================================
echo "\n--- Uploading course cover images ---\n";

$assets_dir = '/var/www/html/moodle_app/assets/images';

foreach ($courses_data as $course_data) {
    if (!isset($created_courses[$course_data['shortname']])) {
        continue;
    }
    $course = $created_courses[$course_data['shortname']];
    $cover_filename = 'course-cover-' . strtolower(str_replace('-', '-', $course_data['shortname'])) . '.png';
    $cover_path = $assets_dir . '/' . $cover_filename;

    if (file_exists($cover_path)) {
        reb_upload_course_cover($course->id, $cover_path, 'cover.png');
        echo "  [OK] Cover for {$course_data['shortname']}\n";
    } else {
        echo "  [WARN] Cover image not found at {$cover_path}\n";
    }
}

// ===========================================================================
// 8. ADDITIONAL SITE SETTINGS
// ===========================================================================
echo "\n--- Applying additional settings ---\n";

set_config('courselistwidth', 'card', 'moodlecourse');
set_config('defaulthomepage', 1);          // My Moodle
set_config('frontpage', '6');              // Show enrolled courses
set_config('frontpageloggedin', '6');
set_config('registerauth', 'email');
set_config('supportname', 'REB E-Learning Support');
set_config('supportemail', 'elearning@reb.rw');
echo "  [OK] Additional settings applied\n";

// ===========================================================================
// 9. RESET CACHES
// ===========================================================================
echo "\n--- Resetting caches ---\n";
if (function_exists('theme_reset_all_caches')) {
    theme_reset_all_caches();
}
purge_all_caches();
echo "  [OK] Caches reset\n";

echo "\n=== Customization Complete ===\n";
echo "Visit " . ($CFG->wwwroot ?? 'http://localhost:8080') . " to see the changes.\n";
