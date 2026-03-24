# Imports

# > Standard Libraries
import io
import logging
import os
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import List, Optional, Tuple

# > Third Party Libraries
import pandas as pd
from PIL import Image


def get_env_variable(var_name: str, default_value: str = None) -> str:
    """
    Retrieve an environment variable's value or use a default value.

    Parameters
    ----------
    var_name : str
        The name of the environment variable.
    default_value : str, optional
        Default value to use if the environment variable is not set.
        Default is None.

    Returns
    -------
    str
        Value of the environment variable or the default value.

    Raises
    ------
    ValueError
        If the environment variable is not set and no default value is
        provided.
    """

    logger = logging.getLogger(__name__)

    value = os.environ.get(var_name)
    if value is None:
        if default_value is None:
            raise ValueError(f"Environment variable {var_name} not set and no default " "value provided.")
        logger.warning("Environment variable %s not set. Using default value: " "%s", var_name, default_value)
        return default_value

    logger.debug("Environment variable %s set to %s", var_name, value)
    return value


def file_to_bytes(path):
    with open(path, "rb") as f:
        return io.BytesIO(f.read())


def setup_image_bytes(segmented_image: Image, original_image: Image) -> Tuple[io.BytesIO, io.BytesIO]:
    """
    Converts both segmented and original images into BytesIO streams for
    further processing.

    Parameters
    ----------
    segmented_image : Image
        The image that has been processed for segmentation.
    original_image : Image
        The original image uploaded by the user.

    Returns
    -------
    Tuple[io.BytesIO, io.BytesIO]
        A tuple containing BytesIO streams for the segmented image and the
        original image.
    """
    segmented_image_bytes = io.BytesIO()
    original_image_bytes = io.BytesIO()

    # Save the segmented image into the BytesIO object
    if segmented_image:
        segmented_image.save(segmented_image_bytes, format="PNG")
        segmented_image_bytes.seek(0)  # Reset the stream position

    # Save the original image into the BytesIO object
    if original_image:
        original_image.save(original_image_bytes, format="PNG")
        original_image_bytes.seek(0)  # Reset the stream position

    return segmented_image_bytes, original_image_bytes


def check_for_segmentation_results(directory: Path, identifier: str) -> Tuple[Optional[Image.Image], Optional[str], str]:
    """
    Checks for the existence of segmentation results within a timeout period.

    Parameters
    ----------
    directory : Path
        The directory path where segmented images are expected.
    identifier : str
        A unique identifier used to locate the specific segmented image file.

    Returns
    -------
    Tuple[Optional[Image.Image], Optional[str], str]
        A tuple containing the segmented image (if found), the path to the
        image (if found), and a status message indicating success or failure.
    """
    timeout = 60  # seconds
    start_time = time.time()
    while time.time() - start_time < timeout:
        image_path = directory / "page" / f"{identifier}.png"
        if image_path.exists():
            logging.info("Segmentation results found.")
            return Image.open(image_path), str(directory / "page"), "Segmentation successful."
        time.sleep(1)
    logging.error("Failed to get the segmented image.")
    return None, None, "Failed to get the segmented image."


def wait_for_xml_update(xml_path: str, lastupdate_path: str) -> bool:
    """
    Waits for an XML file to be updated, with a check against a last update
    timestamp file.

    Parameters
    ----------
    xml_path : str
        The file path to the XML file that is expected to be updated.
    lastupdate_path : str
        The file path to a file storing the last update timestamp of the XML
        file.

    Returns
    -------
    bool
        True if the XML file was updated after the timestamp in
        `lastupdate_path`, False otherwise.
    """
    last_update_time = os.path.getmtime(lastupdate_path)
    timeout = 60  # seconds
    start_time = time.time()

    while (time.time() - start_time) < timeout:
        try:
            # Check if the XML file has been updated
            if os.path.getmtime(xml_path) > last_update_time:
                logging.info("XML file has been successfully updated.")
                os.remove(lastupdate_path)
                return True
        except FileNotFoundError:
            # Handle the case where the XML file might not exist yet
            pass
        time.sleep(1)  # Poll every 1 second

    logging.error("Timeout waiting for XML file to update.")
    return False


def save_cut_images(
    identifier: str,
    image_dir: str = "/tmp/upload",
    captions: Optional[pd.DataFrame] = None,
) -> List[Tuple[Image.Image, Optional[str]]]:
    """
    Processes and collects cut images from a specified directory, potentially
    using captions provided in a DataFrame.

    Parameters
    ----------
    identifier : str
        The identifier used to locate specific images within nested
        directories.
    image_dir : str, optional
        The root directory where images are stored. Defaults to "/tmp/upload".
    captions : Optional[pd.DataFrame], optional
        A DataFrame containing captions for the images, indexed by image file
        base names.

    Returns
    -------
    List[Tuple[Image.Image, Optional[str]]]
        A list of tuples, each containing an Image object and an optional
        caption string if captions are provided.
    """
    images = []
    cut_images_dir = os.path.join(image_dir, identifier, identifier)
    for img_file in os.listdir(cut_images_dir):
        if img_file.endswith(".png"):
            img_path = os.path.join(cut_images_dir, img_file)
            if isinstance(captions, pd.DataFrame):
                base_name = os.path.splitext(img_file)[0]
                images.append((Image.open(img_path), captions.loc[base_name]["text"]))
            else:
                images.append(Image.open(img_path))

    return images


def xml_to_string(xml_path: str) -> str:
    """
    Converts an XML file into a string representation, removing namespace
    prefixes from the tags.

    Parameters
    ----------
    xml_path : str
        The file path of the XML document to be converted.

    Returns
    -------
    str
        A string representation of the XML document with namespace prefixes
        stripped from the tags.
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()
    for elem in root.iter():
        # Splits on '}' and takes the last part, i.e., the actual tag name
        # without namespace
        elem.tag = elem.tag.split("}")[-1]

    return ET.tostring(root, encoding="unicode", method="xml")


def await_directory(directory: Path, timeout: int) -> bool:
    """
    Waits for a directory to become available and not empty within a specified
    timeout.

    Parameters
    ----------
    directory : Path
        The directory path to check for availability and content.
    timeout : int
        The maximum time, in seconds, to wait for the directory to become
        available.

    Returns
    -------
    bool
        True if the directory exists and is not empty before the timeout
        expires, otherwise False.
    """
    start_time = time.time()
    while time.time() - start_time < timeout:
        if directory.is_dir() and any(directory.iterdir()):
            logging.info("Directory with cut images is ready.")
            return True
        time.sleep(1)
    logging.error("Timeout waiting for directory to become available.")
    return False


def await_htr_results(directory: Path, expected_count: int) -> pd.DataFrame:
    """
    Waits for a specific number of Handwriting Text Recognition (HTR) result
    files to appear in the specified directory within a set timeout.

    Parameters
    ----------
    directory : Path
        The directory path where HTR result files are expected to be saved.
    expected_count : int
        The number of HTR result files expected to be saved in the directory.

    Returns
    -------
    pd.DataFrame
        Returns a pandas DataFrame containing HTR results if all expected
        results are processed in time; otherwise, returns an empty DataFrame.
    """
    timeout = 30  # seconds to wait for all results
    start_time = time.time()

    while time.time() - start_time < timeout:
        if len(list(directory.glob("*.txt"))) == expected_count:
            logging.info("All HTR results processed.")
            return collect_htr_results(directory)
        time.sleep(1)

    logging.error("Not all HTR results were processed in time.")
    return pd.DataFrame()


def await_xml_update(xml_path: Path) -> bool:
    """
    Waits for an XML file to be updated after a merge or other operation within
    a set timeout period.

    Parameters
    ----------
    xml_path : Path
        The file path of the XML document to be monitored for updates.

    Returns
    -------
    bool
        True if the XML file is updated within the timeout period, otherwise
        False.
    """
    timeout = 60  # seconds to wait for XML update
    start_time = time.time()
    last_mod_time = os.path.getmtime(xml_path)

    while time.time() - start_time < timeout:
        current_mod_time = os.path.getmtime(xml_path)
        if current_mod_time != last_mod_time:
            logging.info("XML updated successfully.")
            return True
        time.sleep(1)

    logging.error("Timeout waiting for XML update.")
    return False


def await_file(file_path: Path, timeout: int) -> bool:
    """
    Waits for a file to exist within a specified timeout period.

    Parameters
    ----------
    file_path : Path
        The path of the file to check for existence.
    timeout : int
        The time in seconds to wait for the file to appear before timing out.

    Returns
    -------
    bool
        True if the file exists within the timeout period, otherwise False.
    """
    start_time = time.time()
    while time.time() - start_time < timeout:
        if file_path.exists():
            logging.info(f"{file_path.name} found.")
            return True
        time.sleep(1)
    logging.error(f"Timeout waiting for {file_path.name}.")
    return False


def collect_htr_results(directory: Path) -> pd.DataFrame:
    """
    Collects Handwriting Text Recognition (HTR) results from text files within
    a specified directory and organizes them into a pandas DataFrame.

    Parameters
    ----------
    directory : Path
        The directory containing the HTR result text files.

    Returns
    -------
    pd.DataFrame
        A DataFrame containing the identifier, confidence level, and extracted
        text from each HTR result file.
    """
    htr_results = []
    for htr_file in directory.glob("*.txt"):
        with htr_file.open("r") as file:
            for line in file:
                parts = line.strip().split("\t")
                identifier, confidence, text = parts[0], float(parts[2]), parts[3] if len(parts) > 3 else ""
                htr_results.append({"identifier": identifier, "confidence": confidence, "text": text})

    df = pd.DataFrame(htr_results, columns=["identifier", "confidence", "text"])
    df.index = df["identifier"]
    return df
