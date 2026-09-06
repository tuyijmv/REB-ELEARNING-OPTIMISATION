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

require_once(__DIR__ . '/config.php');
require_once($CFG->libdir . '/adminlib.php');
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
// 3. MOOVE BRAND COLORS + CUSTOM SCSS + MODERN UI SETTINGS
// ===========================================================================
echo "\n--- Applying REB brand colors, SCSS and modern UI settings ---\n";

$moove_settings = [
    'brandcolor'          => '#00A0DC', // Rwanda blue
    'secondarymenucolor'  => '#00A651', // Rwanda green
    'fontsite'            => 'Inter',   // Modern font
    'enablecourseindex'   => '1',       // Enable course index
    'loginwelcometitle'   => 'Welcome to REB E-Learning Portal',
    'loginwelcomedescription' => 'Access quality education resources anytime, anywhere. Join thousands of learners across Rwanda.',
    'loginpaneltagline'   => 'Rwanda Education Board',
    'loginstatusers_value' => '50,000+',
    'loginstatusers'      => 'Active Learners',
    'loginstatsites_value'=> '500+',
    'loginstatsites'      => 'Courses Available',
    'loginstatcountries_value' => '1',
    'loginstatcountries'  => 'Country',
    'loginwelcomeback'    => 'Welcome back! Please sign in to continue your learning journey.',
    'loginseparatoror'    => 'or',
    'loginforgotpassword' => 'Forgot your password?',
    'loginstartsignup'    => 'Create your account',
];

foreach ($moove_settings as $key => $value) {
    set_config($key, $value, 'theme_moove');
    echo "  [OK] theme_moove/$key = $value\n";
}

$frontpage_settings = [
    'displaymarketingbox'     => '1',
    'marketingsectionheading' => 'Why Choose REB E-Learning?',
    'marketingsectioncontent' => 'Discover a modern, accessible, and engaging learning experience built for students, teachers, and parents across Rwanda.',
    'marketing1heading'       => 'Quality Education',
    'marketing1content'       => 'Access interactive courses aligned with the national curriculum, designed to foster critical thinking and digital skills.',
    'marketing2heading'       => 'Expert Teachers',
    'marketing2content'       => 'Learn from certified educators with real-world experience, supported by continuous professional development.',
    'marketing3heading'       => 'Flexible Learning',
    'marketing3content'       => 'Study at your own pace with 24/7 access to lessons, assessments, and multimedia resources.',
    'marketing4heading'       => 'Community & Support',
    'marketing4content'       => 'Join a vibrant learning community with personalised support, mentorship, and collaborative tools.',
    'numbersfrontpage'        => '1',
    'numbersfrontpagecontent' => '<h2>Join thousands of learners across Rwanda</h2>
<p>REB E-Learning provides scalable, reliable, and modern digital learning for schools nationwide.</p>',
    'numbersusers'            => 'Active learners on the platform',
    'numberscourses'          => 'Courses available across all levels',
    'slidercount'             => '1',
];

foreach ($frontpage_settings as $key => $value) {
    set_config($key, $value, 'theme_moove');
    echo "  [OK] theme_moove/$key = $value\n";
}

// Configure slider image and text via Moodle file API.
$sliderimage = '/var/www/html/moodle_app/assets/images/image_2.jpg';
$slidertitle = 'Welcome to REB E-Learning Portal';
$slidercaption = 'Empowering Rwandan learners with quality digital education. Access courses, resources, and tools anytime, anywhere.';

$fs = get_file_storage();
$context = context_system::instance();
$fileinfo = new stdClass();
$fileinfo->component = 'theme_moove';
$fileinfo->filearea = 'sliderimage1';
$fileinfo->itemid = 0;
$fileinfo->contextid = $context->id;
$fileinfo->filepath = '/';
$fileinfo->filename = basename($sliderimage);

$existing = $fs->get_file($context->id, 'theme_moove', 'sliderimage1', 0, '/', basename($sliderimage));
if ($existing) {
    $existing->delete();
}
$fs->create_file_from_pathname($fileinfo, $sliderimage);
set_config('slidertitle1', $slidertitle, 'theme_moove');
set_config('slidercap1', $slidercaption, 'theme_moove');
echo "  [OK] theme_moove/slider configured\n";

$custom_scss = '
/* ===== REB E-Learning Custom Styles ===== */
@import url("https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap");

/* ===== Global Typography & Colors ===== */
body, p, li, .text, .card-text, .coursebox .course-summary,
#page-site-index, .main-inner, #region-main, .page-content, #page {
    font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, system-ui, sans-serif !important;
    font-size: 18px !important;
    line-height: 1.7 !important;
    color: #2d3748 !important;
    background-color: #f8fafc !important;
}

h1, h2, h3, h4, h5, h6 {
    font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, system-ui, sans-serif !important;
    font-weight: 700 !important;
    color: #1a237e !important;
    letter-spacing: -0.02em !important;
}
h1 { font-size: 3.2rem !important; }
h2 { font-size: 2.4rem !important; }
h3 { font-size: 2rem !important; }
h4 { font-size: 1.6rem !important; }
h5 { font-size: 1.35rem !important; }
h6 { font-size: 1.15rem !important; }

a {
    color: #00A0DC !important;
}

/* ===== Slider / Hero Carousel ===== */
#mooveslideshow {
    border-radius: 0 0 40px 40px !important;
    overflow: hidden !important;
    box-shadow: 0 8px 32px rgba(0,0,0,0.12) !important;
}
#mooveslideshow .carousel-item img {
    border-radius: 0 0 40px 40px !important;
    object-fit: cover !important;
    height: 420px !important;
}
#mooveslideshow .carousel-caption {
    background: linear-gradient(135deg, rgba(0,160,220,0.88), rgba(0,166,81,0.78)) !important;
    border-radius: 20px !important;
    padding: 2rem !important;
    text-shadow: 0 2px 8px rgba(0,0,0,0.35) !important;
    bottom: 2rem !important;
    left: 50% !important;
    transform: translateX(-50%) !important;
    width: auto !important;
    max-width: 90% !important;
}
#mooveslideshow .carousel-caption h5 {
    color: white !important;
    font-size: 2.2rem !important;
    font-weight: 800 !important;
    margin-bottom: 0.5rem !important;
}
#mooveslideshow .carousel-caption .caption {
    color: rgba(255,255,255,0.95) !important;
    font-size: 1.2rem !important;
    line-height: 1.6 !important;
}
#mooveslideshow .carousel-indicators {
    bottom: 1rem !important;
}

/* ===== Marketing / Feature Section ===== */
#feature {
    padding: 3.5rem 0 !important;
}
#feature .marketing-content {
    color: #4a5568 !important;
    font-size: 1.1rem !important;
    line-height: 1.7 !important;
    margin-bottom: 1.5rem !important;
}
#feature .card {
    border: none !important;
    border-radius: 20px !important;
    background: rgba(255,255,255,0.88) !important;
    backdrop-filter: blur(10px) !important;
    box-shadow: 0 8px 32px rgba(0,0,0,0.08) !important;
    transition: all 0.3s ease !important;
    overflow: hidden !important;
    height: 100% !important;
}
#feature .card:hover {
    transform: translateY(-8px) !important;
    box-shadow: 0 20px 50px rgba(0,0,0,0.14) !important;
    background: rgba(255,255,255,0.95) !important;
}
#feature .card .card-body {
    padding: 2rem !important;
    background: white !important;
}
#feature .icon-lg {
    width: 64px !important;
    height: 64px !important;
    border-radius: 16px !important;
    background: linear-gradient(135deg, #00A0DC, #00A651) !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    box-shadow: 0 6px 20px rgba(0,160,220,0.25) !important;
    padding: 0 !important;
    margin-bottom: 1rem !important;
}
#feature .icon-lg img {
    max-width: 32px !important;
    max-height: 32px !important;
    filter: brightness(0) invert(1) !important;
}
#feature h5 {
    color: #1a237e !important;
    font-size: 1.4rem !important;
    font-weight: 700 !important;
    margin-bottom: 0.75rem !important;
}
#feature .box-content {
    color: #4a5568 !important;
    font-size: 1rem !important;
    line-height: 1.6 !important;
}

/* ===== Numbers Section ===== */
#numbers {
    padding: 3.5rem 0 !important;
}
#numbers .sectionheading h2 {
    color: #1a237e !important;
    font-size: 2rem !important;
    font-weight: 700 !important;
    margin-bottom: 0.5rem !important;
}
#numbers .sectionheading p {
    color: #4a5568 !important;
    font-size: 1.1rem !important;
    line-height: 1.6 !important;
}
#numbers .rate-box {
    background: linear-gradient(135deg, #00A0DC, #00A651) !important;
    border-radius: 20px !important;
    padding: 2rem !important;
    text-align: center !important;
    box-shadow: 0 8px 28px rgba(0,160,220,0.25) !important;
    transition: transform 0.3s ease !important;
    height: 100% !important;
}
#numbers .rate-box:hover {
    transform: translateY(-6px) !important;
}
#numbers .rate-box h3 {
    color: white !important;
    font-size: 3rem !important;
    font-weight: 800 !important;
    margin-bottom: 0.5rem !important;
}
#numbers .rate-box p {
    color: rgba(255,255,255,0.9) !important;
    font-size: 1rem !important;
    margin-bottom: 0 !important;
}
#numbers .rate-box-2 {
    background: linear-gradient(135deg, #003366, #00264D) !important;
    box-shadow: 0 8px 28px rgba(0,51,102,0.25) !important;
}

/* ===== FAQ Section ===== */
#faq {
    padding: 3.5rem 0 !important;
}
#faq h2 {
    color: #1a237e !important;
    font-size: 2rem !important;
    font-weight: 700 !important;
    margin-bottom: 1.5rem !important;
}
#faq .accordion-item {
    border: none !important;
    border-radius: 16px !important;
    margin-bottom: 0.75rem !important;
    box-shadow: 0 4px 16px rgba(0,0,0,0.05) !important;
    overflow: hidden !important;
    background: white !important;
}
#faq .accordion-button {
    border-radius: 16px !important;
    font-weight: 600 !important;
    color: #1a237e !important;
    padding: 1.1rem 1.25rem !important;
    font-size: 1.05rem !important;
    background: white !important;
}
#faq .accordion-button:not(.collapsed) {
    background: linear-gradient(135deg, rgba(0,160,220,0.1), rgba(0,166,81,0.1)) !important;
    color: #1a237e !important;
}
#faq .accordion-body {
    padding: 1.25rem !important;
    color: #4a5568 !important;
    font-size: 1rem !important;
    line-height: 1.6 !important;
    background: white !important;
}

/* ===== Course Cards ===== */
.coursebox {
    border-radius: 20px !important;
    border: none !important;
    box-shadow: 0 4px 20px rgba(0,0,0,0.06) !important;
    transition: all 0.3s ease !important;
    padding: 1.2rem !important;
    background: white !important;
}
.coursebox:hover {
    transform: translateY(-6px) !important;
    box-shadow: 0 16px 40px rgba(0,0,0,0.12) !important;
}
.coursebox .course-title {
    color: #1a237e !important;
    font-size: 1.35rem !important;
    font-weight: 700 !important;
}
.coursebox .course-summary {
    color: #4a5568 !important;
    font-size: 1rem !important;
    line-height: 1.6 !important;
}
.coursebox .course-image {
    border-radius: 16px 16px 0 0 !important;
    object-fit: cover !important;
    height: 200px !important;
}

/* ===== General Improvements ===== */
.card {
    border-radius: 16px !important;
    border: none !important;
    background: white !important;
}
.card-body {
    background: white !important;
}
.btn {
    border-radius: 10px !important;
    font-weight: 600 !important;
    padding: 12px 28px !important;
    font-size: 1rem !important;
}
.block {
    border-radius: 16px !important;
    border: none !important;
    box-shadow: 0 4px 16px rgba(0,0,0,0.05) !important;
    background: white !important;
}
.region-content {
    border-radius: 16px !important;
}
.page-content, .main-inner, #region-main-box {
    background: transparent !important;
}

/* ===== Login Page ===== */
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
.login-container .card-body,
#page-login-index .card-body {
    background: rgba(255,255,255,0.95) !important;
}

/* ===== Navbar & Header ===== */
.navbar {
    background: linear-gradient(135deg, #003366 0%, #00264D 100%) !important;
    box-shadow: 0 2px 10px rgba(0,0,0,0.15);
    backdrop-filter: blur(10px);
}
.navbar .navbar-brand,
.navbar .navbar-nav .nav-link {
    color: white !important;
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

// Enroll admin user in all created courses so they appear in My Moodle
echo "\n--- Enrolling admin user in courses ---\n";
$admin = $DB->get_record('user', ['username' => 'admin']);
if ($admin) {
    foreach ($created_courses as $shortname => $course) {
        $existing_enrolment = $DB->get_record('user_enrolments', [
            'userid' => $admin->id,
            'enrolid' => $DB->get_field('enrol', 'id', ['courseid' => $course->id, 'enrol' => 'manual'])
        ]);
        if (!$existing_enrolment) {
            $enrolid = $DB->get_field('enrol', 'id', ['courseid' => $course->id, 'enrol' => 'manual']);
            if ($enrolid) {
                $DB->insert_record('user_enrolments', (object)[
                    'status'      => 0,
                    'enrolid'     => $enrolid,
                    'userid'      => $admin->id,
                    'timestart'   => 0,
                    'timeend'     => 0,
                    'timecreated' => time(),
                    'timemodified'=> time(),
                ]);
                echo "  [OK] Enrolled admin in {$shortname}\n";
            } else {
                echo "  [WARN] No manual enrolment instance found for {$shortname}\n";
            }
        } else {
            echo "  [SKIP] Admin already enrolled in {$shortname}\n";
        }
    }
} else {
    echo "  [WARN] Admin user not found for enrolment\n";
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
// 8. ADDITIONAL SITE SETTINGS + MODERN HOME PAGE
// ===========================================================================
echo "\n--- Applying additional settings and modern home page ---\n";

set_config('courselistwidth', 'card', 'moodlecourse');
set_config('defaulthomepage', 1);          // My Moodle
set_config('frontpage', '6');              // Show enrolled courses
set_config('frontpageloggedin', '6');
set_config('registerauth', 'email');
set_config('supportname', 'REB E-Learning Support');
set_config('supportemail', 'elearning@reb.rw');
set_config('fullname', 'REB E-Learning Portal', 'core');
set_config('summary', '<p>Welcome to the <strong>Rwanda Education Board E-Learning Portal</strong>. Access quality education resources anytime, anywhere.</p>', 'core');
set_config('lang', 'en');
set_config('timezone', 'Africa/Kigali');
set_config('newsitems', 5);
set_config('numcourses', 50);
set_config('maxeditingtime', 18000);
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
