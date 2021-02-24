import chroma, common, images, vmath, blends, paths, masks

type
  PaintKind* = enum
    pkSolid
    pkImageFill
    pkImageFit
    pkImageStretch
    pkImageTile
    pkGradientLinear
    pkGradientRadial
    pkGradientAngular
    pkGradientDiamond

  Paint* = ref object
    blendMode*: BlendMode
    kind*: PaintKind
    color*: ColorRGBA
    image*: Image
    mat*: Mat3
    gradientHandlePositions*: seq[Vec2]
    gradientStops*: seq[ColorStop]

  ColorStop* = object
    ## Represents color on a gradient curve.
    color*: Color
    position*: float32

proc toLineSpace(at, to, point: Vec2): float32 =
  ## Convert position on to where it would fall on a line between at and to.
  let
    d = to - at
    det = d.x*d.x + d.y*d.y
  return (d.y*(point.y-at.y)+d.x*(point.x-at.x))/det

proc gradientPut(image: Image, x, y: int, a: float32, stops: seq[ColorStop]) =
  ## Put an gradient color based on the "a" - were are we related to a line.
  var
    index = -1
  for i, stop in stops:
    if stop.position < a:
      index = i
    if stop.position > a:
      break
  var color: Color
  if index == -1:
    # first stop solid
    color = stops[0].color
  elif index + 1 >= stops.len:
    # last stop solid
    color = stops[index].color
  else:
    let
      gs1 = stops[index]
      gs2 = stops[index+1]
    color = mix(
      gs1.color,
      gs2.color,
      (a - gs1.position) / (gs2.position - gs1.position)
    )
  image.setRgbaUnsafe(x, y, color.rgba.toPremultipliedAlpha())

proc fillLinearGradient*(
  image: Image,
  at, to: Vec2,
  stops: seq[ColorStop]
) =
  ## Linear gradient.
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let xy = vec2(x.float32, y.float32)
      let a = toLineSpace(at, to, xy)
      image.gradientPut(x, y, a, stops)

proc fillRadialGradient*(
  image: Image,
  center, edge, skew: Vec2,
  stops: seq[ColorStop]
) =
  ## Radial gradient.
  ## start, stop, and skew.
  let
    distanceX = dist(center, edge)
    distanceY = dist(center, skew)
    gradientAngle = normalize(center - edge).angle().fixAngle()
    mat = (
      translate(center) *
      rotationMat3(-gradientAngle) *
      scale(vec2(distanceX, distanceY))
    ).inverse()
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let xy = vec2(x.float32, y.float32)
      let b = (mat * xy).length()
      image.gradientPut(x, y, b, stops)

proc fillAngularGradient*(
  image: Image,
  center, edge, skew: Vec2,
  stops: seq[ColorStop]
) =
  # TODO: make edge between start and end anti-aliased.
  let
    gradientAngle = normalize(edge - center).angle().fixAngle()
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let
        xy = vec2(x.float32, y.float32)
        angle = normalize(xy - center).angle()
        a = (angle + gradientAngle + PI/2).fixAngle() / 2 / PI + 0.5
      image.gradientPut(x, y, a, stops)

proc fillDiamondGradient*(
  image: Image,
  center, edge, skew: Vec2,
  stops: seq[ColorStop]
) =
  # TODO: implement GRADIENT_DIAMOND, now will just do GRADIENT_RADIAL
  let
    distance = dist(center, edge)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let xy = vec2(x.float32, y.float32)
      let a = (center - xy).length() / distance
      image.gradientPut(x, y, a, stops)

proc fillPath*(
  image: Image,
  path: SomePath,
  paint: Paint,
  windingRule = wrNonZero,
) {.inline.} =
  var mask = newMask(image.width, image.height)
  var fill = newImage(image.width, image.height)
  mask.fillPath(parseSomePath(path), windingRule)

  case paint.kind:
    of pkSolid:
      fill.fill(paint.color.toPremultipliedAlpha())
    of pkImageFill:
      discard
    of pkImageFit:
      discard
    of pkImageStretch:
      discard
    of pkImageTile:
      discard
    of pkGradientLinear:
      discard
    of pkGradientRadial:
      fill.fillRadialGradient(
        paint.gradientHandlePositions[0],
        paint.gradientHandlePositions[1],
        paint.gradientHandlePositions[2],
        paint.gradientStops
      )
    of pkGradientAngular:
      discard
    of pkGradientDiamond:
      discard

  fill.draw(mask, blendMode = bmMask)
  image.draw(fill, blendMode = paint.blendMode)
