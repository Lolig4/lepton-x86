use std::fs::File;
use std::io::Read;
use zip::result::ZipError;
use zip::ZipArchive;
use axmldecoder::{Element, Node};
use clap::{Arg, Command};

fn peel_element(n: &Node) -> Result<&Element, String> {
    match n {
        Node::Element(n) => return Ok(n),
        Node::Cdata(n) => Err(format!("Expected Element, found Cdata in {:?}", n)),
    }
}

fn filter_children<'a>(node: &'a Node, name: &'a str) -> Result<impl Iterator<Item = &'a Node>, String> {
    let node = peel_element(node)?;
    return Ok(node.get_children()
                  .iter()
                  .filter(move |n| match n {
                      Node::Element(e) => e.get_tag() == name,
                      Node::Cdata(_) => false,
                  }))
}

fn only_child<'a>(node: &'a Node, name: &'a str) -> Result<&'a Node, String> {
    let mut iter = filter_children(node, name)?;
    match (iter.next(), iter.next()) {
        (Some(first), None) => Ok(first),
        (None, _) => Err(format!("Expected one <{}> child, found none", name)),
        (Some(_), Some(_)) => Err(format!("Expected one <{}> child, found multiple", name)),
    }
}

fn read_xml(file_path: &str) -> Result<Vec<u8>, ZipError> {
    let file = File::open(file_path)?;
    let mut manifest_data = Vec::new();
    // First, try to load it as a `.zip`
    match ZipArchive::new(file) {
        Ok(mut zip) => {
            let mut manifest_file = zip.by_name("AndroidManifest.xml")?;
            manifest_file.read_to_end(&mut manifest_data)?;
        }
        Err(e) => {
            // If it's not a `.zip` file, if the filename ends in `.xml`, just read it in:
            if !file_path.ends_with(".xml") {
                return Err(e.into());
            }
            let mut file = File::open(file_path)?;
            file.read_to_end(&mut manifest_data)?;
        }
    };
    return Ok(manifest_data);
}

fn vprint(msg: String, verbose: bool) {
    if verbose {
        println!("{}", msg);
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Define the CLI
    let matches = Command::new("apk-info-extractor")
        .version("1.0")
        .about("Extracts information from the AndroidManifest.xml in .apk files")
        .arg(
            Arg::new("apk")
                .help("Path to the APK file")
                .required(true)
                .index(1),
        )
        .arg(
            Arg::new("print-app-id")
                 .long("print-app-id")
                 .help("Print the app id")
                 .action(clap::ArgAction::SetTrue),
        )
        .arg(
            Arg::new("print-activity-name")
                 .long("print-activity-name")
                 .help("Print the activity name")
                 .action(clap::ArgAction::SetTrue)
        )
        .arg(
            Arg::new("print-app-version")
                 .long("print-app-version")
                 .help("Print the app version")
                 .action(clap::ArgAction::SetTrue)
        )
        .arg(
            Arg::new("print-min-sdk-version")
                 .long("print-min-sdk-version")
                 .help("Print the minimum sdk version")
                 .action(clap::ArgAction::SetTrue)
        )
        .arg(
            Arg::new("verbose")
                .short('v')
                .long("verbose")
                .help("Enable verbose output")
                .action(clap::ArgAction::SetTrue)
        )
        .get_matches();

    let apk_path = matches.get_one::<String>("apk").unwrap();
    let print_app_id = matches.get_flag("print-app-id");
    let print_activity_name = matches.get_flag("print-activity-name");
    let print_app_version = matches.get_flag("print-app-version");
    let print_min_sdk_version = matches.get_flag("print-min-sdk-version");
    let verbose = matches.get_flag("verbose");

    if !print_activity_name && !print_app_id && !print_app_version && !print_min_sdk_version {
        return Err("Must provide one of --print-app-id, --print-activity-name, --print-app-version --print-min-sdk-version!".into())
    }

    // Support running on either an `.apk` or a `.xml` file directly
    let manifest_data = read_xml(apk_path)?;

    // Use `axmldecoder` to parse the input binary XML file
    let xml = axmldecoder::parse(&manifest_data)?;
    let manifest = xml.get_root().as_ref().unwrap();

    // Get package name from top-level manifest element
    let package_name = &peel_element(manifest)?.get_attributes()["package"];
    if print_app_id {
        println!("{}", package_name);
    }

    // Get versionCode from top-level manifest element
    let app_version = peel_element(manifest)?.get_attributes().get("android:versionCode").map(|s| s.as_str());
    if print_app_version {
        println!("{}", app_version.unwrap_or("none"));
    }

    // Search for launchable activity
    let application = only_child(manifest, "application")?;
    let activities = filter_children(application, "activity")?;
    let uses_sdk = only_child(manifest, "uses-sdk")?;

    // Get the minimum sdk version from the uses-sdk element
    let min_sdk_version = peel_element(uses_sdk)?.get_attributes().get("android:minSdkVersion").map(|s| s.as_str());
    if print_min_sdk_version {
        println!("{}", min_sdk_version.unwrap_or("none"));
    }

    'activities: for activity in activities {
        // If we can't find an activity name, continue
        let activity_name = match peel_element(activity)?.get_attributes().get("android:name") {
            Some(name) => name,
            None => {
                vprint(format!("Skipping activity {:?} due to no 'android:name'", peel_element(activity)?), verbose);
                continue
            },
        };

        // Iterate over all `intent-filter` tags
        let intent_filters = match filter_children(activity, "intent-filter") {
            Ok(intent_filters) => intent_filters,
            Err(e) => {
                vprint(format!("Skipping activity {:?} due to no 'intent-filter' child: {}", activity_name, e), verbose);
                continue
            },
        };
        for intent_filter in intent_filters {
            // Find `action` and `catgeory` tags:
            let actions = match filter_children(intent_filter, "action") {
                Ok(actions) => actions,
                Err(e) => {
                    vprint(format!("Skipping intent_filter {:?} in activity {:?} due to no 'action' children for intent-filter: {}", intent_filter, activity_name, e), verbose);
                    continue
                },
            };
            let categories = match filter_children(intent_filter, "category") {
                Ok(categories) => categories,
                Err(e) => {
                    vprint(format!("Skipping intent_filter {:?} activity {:?} due to no 'category' children for intent-filter: {}", intent_filter, activity_name, e), verbose);
                    continue
                },
            };

            fn get_any_matching_attribute<'a>(nodes: impl Iterator<Item = &'a Node>, key: &str, val: &str) -> Result<bool, String> {
                for node in nodes {
                    match peel_element(node)?.get_attributes().get(key) {
                        Some(key_val) => {
                            if key_val == val {
                                return Ok(true);
                            }
                        }
                        None => continue,
                    }
                }
                return Ok(false);
            }

            if !get_any_matching_attribute(actions, "android:name", "android.intent.action.MAIN")? {
                vprint(format!("Skipping intent_filter {:?} in activity {:?} due to no 'android.intent.action.MAIN' action", intent_filter, activity_name), verbose);
                continue;
            }

            if !get_any_matching_attribute(categories, "android:name", "android.intent.category.LAUNCHER")? {
                vprint(format!("Skipping intent_filter {:?} in activity {:?} due to no 'android.intent.category.LAUNCHER' category", intent_filter, activity_name), verbose);
                continue;
            }
        
            // Otherwise, report this activity name and break out
            if print_activity_name {
                println!("{}", activity_name);
                break 'activities;
            }
        }
    }
    return Ok(());
}
