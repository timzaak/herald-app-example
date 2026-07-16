// Not imported at runtime; consumed by build_runner to generate
// packages/api_client/.
//
// Regenerate with:
//   dart run build_runner build --delete-conflicting-outputs
//
// To filter the source spec first (auth only), see tool/filter_spec.sh.
import 'package:openapi_generator_annotations/openapi_generator_annotations.dart';

@Openapi(
  generatorName: Generator.dio,
  inputSpec: InputSpec(path: 'packages/api_client/api_spec.json'),
  outputDirectory: 'packages/api_client',
  runSourceGenOnOutput: true,
  // Spec uses OpenAPI 3.1; generator falsely flags license.identifier.
  // Broken $ref are caught by tool/filter_spec.sh recursion, so skipping
  // validation here only suppresses the 3.1 license false-positive.
  skipSpecValidation: true,
  additionalProperties: DioProperties(
    pubName: 'api_client',
    pubAuthor: 'ai-agent-app',
    pubLibrary: 'api_client',
    // Use spec-compliant polymorphic discriminator behavior.
    legacyDiscriminatorBehavior: false,
  ),
)
class OpenApiGenConfig {}
