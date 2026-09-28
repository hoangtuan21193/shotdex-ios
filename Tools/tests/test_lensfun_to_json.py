"""FS-03.16b AC-b7, AC-b8 — the Lensfun table refresh.

Run: python3 -m unittest discover -s Tools/tests
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "lensfun-to-json.py"

XML = """<lensdatabase>
  <camera><maker>Nikon</maker><model>D800E</model><mount>Nikon F AF</mount><cropfactor>1</cropfactor></camera>
  <lens>
    <maker>Nikon</maker><model>Nikkor 24mm f/1.8G</model><mount>Nikon F AF</mount><cropfactor>1</cropfactor>
    <calibration>
      <distortion model="ptlens" focal="24" a="0.01" b="-0.03" c="0"/>
      <tca model="poly3" focal="24" br="-0.0001" vr="1.0003" bb="0.0001" vb="0.9998"/>
      <vignetting model="pa" focal="24" aperture="1.8" distance="10" k1="-0.5" k2="0.2" k3="-0.05"/>
    </calibration>
  </lens>
  <lens>
    <maker>Sigma</maker><model>35mm f/1.4 DG HSM | A</model><mount>Nikon F AF</mount><cropfactor>1</cropfactor>
    <calibration>
      <vignetting model="pa" focal="35" aperture="1.4" distance="10" k1="-0.6" k2="0.3" k3="-0.1"/>
    </calibration>
  </lens>
</lensdatabase>
"""


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], capture_output=True, text=True)


class LensfunToJSONTests(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp())
        self.db = self.work / "db"
        self.db.mkdir()
        (self.db / "nikon.xml").write_text(XML)
        self.output = self.work / "lensfun-profiles.json"

    def test_keeps_vignetting_tca_and_lenses_without_distortion(self):
        result = run(self.db, self.output, "--commit", "abc123", "--date", "2026-09-24")
        self.assertEqual(result.returncode, 0, result.stderr)
        table = json.loads(self.output.read_text())
        self.assertEqual(table["lensfunCommit"], "abc123")
        self.assertEqual(table["lensfunDate"], "2026-09-24")
        nikkor, sigma = table["lenses"]
        self.assertEqual(nikkor["vignettingPA"], [[24.0, 1.8, 10.0, -0.5, 0.2, -0.05]])
        self.assertEqual(nikkor["tca"][0]["vr"], 1.0003)
        # Vignetting only — skipped before FS-03.16.
        self.assertEqual(sigma["distortion"], [])
        self.assertEqual(len(sigma["vignettingPA"]), 1)

    def test_previous_prints_one_line_and_the_ids_that_went(self):
        previous = self.work / "previous.json"
        previous.write_text(json.dumps({"cameras": [], "lenses": [
            {"maker": "Nikon", "model": "Nikkor 24mm f/1.8G", "cropFactor": 1.0, "distortion": []},
            {"maker": "Canon", "model": "EF 50mm f/1.8", "cropFactor": 1.0, "distortion": []},
        ]}))
        result = run(self.db, self.output, "--previous", previous, "--commit", "c", "--date", "d")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Lens profiles 2 → 2 (+0) · vignetting 0 → 2 (+2) · TCA 0 → 1 (+1) · cameras 0 → 1 (+1)", result.stdout)
        self.assertIn("lens id gone: Canon|EF 50mm f/1.8|1.0", result.stdout)

    def test_empty_directory_fails_and_leaves_the_table(self):
        empty = self.work / "empty"
        empty.mkdir()
        self.output.write_text("unchanged")
        result = run(empty, self.output)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), "unchanged")

    def test_over_the_ceiling_fails_and_leaves_the_table(self):
        self.output.write_text("unchanged")
        result = run(self.db, self.output, "--ceiling", "100")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ceiling", result.stderr)
        self.assertEqual(self.output.read_text(), "unchanged")

    def test_a_drop_of_more_than_one_percent_fails(self):
        previous = self.work / "previous.json"
        previous.write_text(json.dumps({"cameras": [], "lenses": [
            {"maker": "X", "model": str(n), "cropFactor": 1.0, "distortion": []} for n in range(10)
        ]}))
        self.output.write_text("unchanged")
        result = run(self.db, self.output, "--previous", previous)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main()
