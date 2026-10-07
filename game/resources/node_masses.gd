class_name NodeMasses
extends RefCounted
## Works out what each node of a rig weighs, following upstream's `recalculateNodeMasses`.
##
## Four rules, applied in order, and the order matters:
##
## 1. A node that states a weight of its own gets it. The hero truck states one for every
##    node it declares — 18 kg under the frame rails, 14 kg around the engine, 2.3 kg over
##    the panels — which is 1.2 tonnes of stated mass before anything is computed.
## 2. A node asking for a share of the rig's cargo mass without naming a figure splits it
##    with every other node that asked.
## 3. The rig's dry mass is spread over everything else by beam length: a node joined by
##    long beams is holding up more structure than one joined by short ones. This is
##    upstream's "average linear density" pass, and it is the only part that is computed
##    rather than stated.
## 4. Anything still lighter than the rig's minimass is raised to it.
##
## Tyre nodes sit outside all four. Their mass comes from the wheel row that generated them
## and neither the distribution nor the floor touches it, so a tyre weighs what the file
## says whatever the structure around it works out to.
##
## Using the minimass floor for every node instead is not a small simplification. On the
## hero truck it turns a 1.6 tonne truck with a heavy nose into a uniformly light one, and
## a node that should weigh 18 kg into one weighing 3.2 — which is a fifth of the inertia
## resisting the stiff beams attached to it, and therefore a fifth of the timestep.

## Upstream's DEFAULT_MINIMASS, for a rig that states no minimass of its own.
const DEFAULT_MINIMASS_KG: float = 50.0


## Returns one mass per node, in kilograms.
static func distribute(truck: TruckParser) -> PackedFloat32Array:
    var count: int = truck.nodes.size()
    var masses: PackedFloat32Array = PackedFloat32Array()
    masses.resize(count)
    var first_tyre: int = truck.generated_from if truck.generated_from >= 0 else count

    var cargo_share: float = 0.0
    if not truck.cargo_share_nodes.is_empty():
        cargo_share = (
            (truck.drivetrain["cargo_mass_kg"] as float) / float(truck.cargo_share_nodes.size())
        )
    for i: int in count:
        var stated: float = truck.node_mass[i] if i < truck.node_mass.size() else -1.0
        if i >= first_tyre:
            # Generated tread. Its mass came from the wheel's own row.
            masses[i] = maxf(stated, 0.0)
        elif stated >= 0.0:
            masses[i] = stated
        else:
            masses[i] = 0.0
    for index: int in truck.cargo_share_nodes:
        if index < first_tyre:
            masses[index] = cargo_share

    # Total beam half-length seen by the nodes that share the dry mass. A beam end on a
    # tyre node contributes nothing, because the tyre is not carrying the structure, and a
    # virtual beam contributes nothing at either end: upstream skips `BEAM_VIRTUAL` in both
    # passes, and a wheel's rigidity beams are virtual.
    var total_length: float = 0.0
    for i: int in range(0, truck.beams.size(), 2):
        if truck.beam_table.virtual_beam[i / 2] != 0:
            continue
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        var half: float = truck.nodes[a].distance_to(truck.nodes[b]) * 0.5
        if a < first_tyre:
            total_length += half
        if b < first_tyre:
            total_length += half
    var dry_mass: float = truck.drivetrain["dry_mass_kg"] as float
    if total_length > 0.0 and dry_mass > 0.0:
        for i: int in range(0, truck.beams.size(), 2):
            if truck.beam_table.virtual_beam[i / 2] != 0:
                continue
            var a: int = truck.beams[i]
            var b: int = truck.beams[i + 1]
            var half_mass: float = (
                truck.nodes[a].distance_to(truck.nodes[b]) * dry_mass / total_length * 0.5
            )
            if a < first_tyre:
                masses[a] += half_mass
            if b < first_tyre:
                masses[b] += half_mass

    var floor_kg: float = truck.minimass_kg if truck.minimass_kg > 0.0 else DEFAULT_MINIMASS_KG
    for i: int in first_tyre:
        masses[i] = maxf(masses[i], floor_kg)
    return masses
